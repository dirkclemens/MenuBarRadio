import AVFoundation
import AppKit
import Combine
import Foundation
import OSLog

/// Core playback engine: stream control, metadata parsing, and settings persistence.
@MainActor
final class RadioPlayer: NSObject, ObservableObject {
    // MARK: Playback state

    @Published private(set) var isPlaying = false
    /// `true` while playback was requested but the stream is still connecting/buffering.
    @Published private(set) var isBuffering = false
    /// User-facing description of the last stream problem (cleared once audio plays).
    @Published private(set) var playbackError: String?
    @Published private(set) var currentStation: RadioStation?
    @Published private(set) var nowPlaying = NowPlayingMetadata()
    @Published private(set) var songHistory: [SongHistoryEntry] = [] {
        didSet { schedulePersist() }
    }

    // MARK: Settings

    @Published var stations: [RadioStation] {
        didSet { schedulePersist() }
    }
    @Published var menuBarDisplay: MenuBarDisplayConfiguration {
        didSet { schedulePersist() }
    }
    @Published var volume: Float {
        didSet {
            player.volume = volume
            schedulePersist()
        }
    }
    @Published var metadataRefreshSeconds: Double {
        didSet { schedulePersist() }
    }
    @Published var autoPlayOnLaunch: Bool {
        didSet { schedulePersist() }
    }
    @Published var restoreArtworkPopupOnLaunch: Bool {
        didSet { schedulePersist() }
    }
    /// CoreAudio UID of the preferred output device; `nil` follows the system default.
    @Published var selectedOutputDeviceUID: String? {
        didSet {
            applyOutputDeviceSelection()
            schedulePersist()
        }
    }
    @Published var showDockIcon: Bool {
        didSet {
            DockIconManager.apply(showDockIcon: showDockIcon)
            schedulePersist()
        }
    }
    @Published var songHistoryLimit: Int {
        didSet {
            if songHistoryLimit < 0 { songHistoryLimit = 0 }
            trimSongHistory()
            schedulePersist()
        }
    }

    /// Shared output device list (also used by the settings and popover UI).
    let audioDevices = AudioDeviceManager()

    // MARK: Private state

    private let settingsStore = SettingsStore()
    private let enrichmentService = MusicMetadataEnrichmentService()
    private let player = AVPlayer()
    private let log = Logger(subsystem: "de.adcore.MenuBarRadio", category: "player")

    private var metadataTask: Task<Void, Never>?
    private var metadataEnrichmentTask: Task<Void, Never>?
    private var persistTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var reconnectAttempts = 0
    private var pausedAt: Date?
    private var embeddedArtworkFileURL: URL?
    private var cancellables = Set<AnyCancellable>()
    private var itemCancellables = Set<AnyCancellable>()

    private static let maxReconnectAttempts = 5
    /// After a pause longer than this, resuming reloads the stream so playback is live again
    /// instead of continuing from a stale buffer.
    private static let liveResumeThreshold: TimeInterval = 10

    override init() {
        let settings = settingsStore.load()
        self.stations = settings.stations
        self.menuBarDisplay = settings.menuBarDisplay
        self.volume = settings.volume
        self.metadataRefreshSeconds = settings.metadataRefreshSeconds
        self.autoPlayOnLaunch = settings.autoPlayOnLaunch
        self.restoreArtworkPopupOnLaunch = settings.restoreArtworkPopupOnLaunch
        self.selectedOutputDeviceUID = settings.selectedOutputDeviceUID
        self.showDockIcon = settings.showDockIcon
        self.songHistoryLimit = max(0, settings.songHistoryLimit)
        self.songHistory = settings.songHistory
        super.init()

        // Migrate the numeric device ID used by ≤ 1.0.2 to a persistent UID.
        if selectedOutputDeviceUID == nil, let legacyID = settings.legacyOutputDeviceID, legacyID != 0 {
            selectedOutputDeviceUID = audioDevices.uid(forDeviceID: legacyID)
        }

        player.volume = volume
        applyOutputDeviceSelection()
        trimSongHistory()
        observePlayer()

        if let selectedID = settings.selectedStationID ?? stations.first?.id {
            selectStation(id: selectedID, autoPlay: autoPlayOnLaunch)
        }
    }

    // MARK: - Menu bar text

    /// Builds the menu bar label based on current metadata and settings.
    var menuBarLabel: String {
        var parts: [String] = []
        if menuBarDisplay.showArtist, let artist = nowPlaying.artist, !artist.isEmpty {
            parts.append(artist)
        }
        if menuBarDisplay.showTitle, let title = nowPlaying.title, !title.isEmpty {
            parts.append(title)
        }
        if menuBarDisplay.showYear, let year = nowPlaying.releaseYear ?? nowPlaying.year, !year.isEmpty {
            parts.append(year)
        }

        let text: String
        if parts.isEmpty {
            text = menuBarDisplay.showStationNameFallback ? (currentStation?.name ?? "") : ""
        } else {
            text = parts.joined(separator: " • ")
        }

        if text.count > menuBarDisplay.maxLength {
            return String(text.prefix(menuBarDisplay.maxLength)) + "…"
        }
        return text
    }

    /// Builds the tooltip text with richer metadata details.
    var menuBarTooltip: String {
        var lines: [String] = []
        if let stationName = currentStation?.name {
            lines.append("Station: \(stationName)")
        }
        if let title = nowPlaying.title {
            lines.append("Title: \(title)")
        }
        if let artist = nowPlaying.artist {
            lines.append("Artist: \(artist)")
        }
        if let album = nowPlaying.album {
            lines.append("Album: \(album)")
        }
        if let year = nowPlaying.year {
            lines.append("Year: \(year)")
        }
        lines.append(contentsOf: nowPlaying.displayExtraLines.prefix(8))
        return lines.isEmpty ? "Streaming Radio" : lines.joined(separator: "\n")
    }

    /// UID handed to other players (e.g. the directory preview) so they use the same output.
    var effectiveOutputDeviceUID: String? {
        guard let uid = selectedOutputDeviceUID, audioDevices.contains(uid: uid) else { return nil }
        return uid
    }

    // MARK: - Transport

    func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }

    func play() {
        guard let station = currentStation else { return }

        let pausedTooLong = pausedAt.map { Date().timeIntervalSince($0) > Self.liveResumeThreshold } ?? false
        if player.currentItem == nil || player.currentItem?.status == .failed || pausedTooLong {
            loadItem(for: station)
        }
        pausedAt = nil
        reconnectAttempts = 0
        playbackError = nil

        player.play()
        isPlaying = true
        startMetadataPollingIfNeeded()
    }

    func pause() {
        player.pause()
        isPlaying = false
        isBuffering = false
        pausedAt = Date()
        reconnectTask?.cancel()
        reconnectTask = nil
        metadataTask?.cancel()
        metadataTask = nil
        if !restoreArtworkPopupOnLaunch {
            ArtworkPopupWindowController.shared.close()
        }
    }

    /// Switches the player to a given station and optionally starts playback.
    func selectStation(id: UUID, autoPlay: Bool? = nil) {
        guard let station = stations.first(where: { $0.id == id }) else { return }
        let shouldAutoPlay = autoPlay ?? isPlaying

        currentStation = station
        nowPlaying = NowPlayingMetadata()
        playbackError = nil
        reconnectTask?.cancel()
        reconnectAttempts = 0
        loadItem(for: station)

        if shouldAutoPlay {
            play()
        } else {
            pause()
        }
        schedulePersist()
    }

    // MARK: - Station list

    func addStation() {
        stations.append(RadioStation(name: "New Station", streamURL: "https://"))
    }

    func appendStation(_ station: RadioStation, makeCurrent: Bool = false, autoPlay: Bool = false) {
        stations.append(station)
        if makeCurrent {
            selectStation(id: station.id, autoPlay: autoPlay)
        }
    }

    func updateStation(_ station: RadioStation) {
        guard let index = stations.firstIndex(where: { $0.id == station.id }) else { return }
        let streamChanged = stations[index].streamURL != station.streamURL
            || currentStation?.streamURL != station.streamURL
            || currentStation?.metadataURL != station.metadataURL
        stations[index] = station
        guard currentStation?.id == station.id else { return }
        currentStation = station
        // Only reconnect when something that affects playback actually changed.
        guard streamChanged else { return }
        if isPlaying {
            selectStation(id: station.id, autoPlay: true)
        } else {
            loadItem(for: station)
        }
    }

    func deleteStation(id: UUID) {
        stations.removeAll { $0.id == id }
        handleDeletedStationIDs([id])
    }

    /// Replaces the full station list while keeping a valid selection if possible.
    func replaceStations(with newStations: [RadioStation]) {
        stations = newStations

        guard let first = newStations.first else {
            stopAndClearCurrentStation()
            return
        }

        if let currentID = currentStation?.id, let match = newStations.first(where: { $0.id == currentID }) {
            currentStation = match
            return
        }

        selectStation(id: first.id, autoPlay: isPlaying)
    }

    func toggleFavorite(id: UUID) {
        guard let index = stations.firstIndex(where: { $0.id == id }) else { return }
        stations[index].isFavorite.toggle()
        if currentStation?.id == id {
            currentStation = stations[index]
        }
    }

    /// Writes pending settings immediately (used on app termination).
    func persistNow() {
        persistTask?.cancel()
        persistTask = nil
        settingsStore.save(
            AppSettings(
                stations: stations,
                selectedStationID: currentStation?.id,
                menuBarDisplay: menuBarDisplay,
                volume: volume,
                metadataRefreshSeconds: metadataRefreshSeconds,
                autoPlayOnLaunch: autoPlayOnLaunch,
                restoreArtworkPopupOnLaunch: restoreArtworkPopupOnLaunch,
                selectedOutputDeviceUID: selectedOutputDeviceUID,
                showDockIcon: showDockIcon,
                songHistoryLimit: songHistoryLimit,
                songHistory: songHistory
            )
        )
    }

    // MARK: - Player item lifecycle

    private func observePlayer() {
        player.publisher(for: \.timeControlStatus)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                guard let self else { return }
                self.isBuffering = self.isPlaying && status == .waitingToPlayAtSpecifiedRate
                if status == .playing {
                    self.reconnectAttempts = 0
                    self.playbackError = nil
                }
            }
            .store(in: &cancellables)

        audioDevices.$devices
            .dropFirst()
            // @Published emits before the value is stored; hop once so `devices` is current.
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                // Re-route when the preferred device appears/disappears (e.g. headphones, AirPlay).
                self?.applyOutputDeviceSelection()
            }
            .store(in: &cancellables)

        $nowPlaying
            .map { TrackFingerprint(metadata: $0) }
            .removeDuplicates()
            .sink { [weak self] fingerprint in
                self?.scheduleEnrichment(for: fingerprint)
                self?.recordHistory(for: fingerprint)
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)
            .sink { [weak self] _ in self?.persistNow() }
            .store(in: &cancellables)
    }

    /// Creates a fresh player item for the station and wires up failure handling.
    private func loadItem(for station: RadioStation) {
        itemCancellables.removeAll()
        guard let url = URL(string: station.streamURL.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme != nil
        else {
            player.replaceCurrentItem(with: nil)
            playbackError = "Invalid stream URL."
            return
        }

        let item = Self.makePlayerItem(for: url)
        let output = AVPlayerItemMetadataOutput(identifiers: nil)
        output.setDelegate(self, queue: .main)
        item.add(output)

        item.publisher(for: \.status)
            .filter { $0 == .failed }
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak item] _ in
                self?.handlePlaybackFailure(item?.error)
            }
            .store(in: &itemCancellables)

        NotificationCenter.default.publisher(for: AVPlayerItem.failedToPlayToEndTimeNotification, object: item)
            .map { $0.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] error in self?.handlePlaybackFailure(error) }
            .store(in: &itemCancellables)

        // A live stream "ending" means the server closed the connection.
        NotificationCenter.default.publisher(for: AVPlayerItem.didPlayToEndTimeNotification, object: item)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.handlePlaybackFailure(nil) }
            .store(in: &itemCancellables)

        player.replaceCurrentItem(with: item)
        player.volume = volume
        pausedAt = nil
    }

    /// Retries the stream with exponential backoff (2, 4, 8, 16, 30 s) before giving up.
    private func handlePlaybackFailure(_ error: Error?) {
        guard isPlaying, let stationID = currentStation?.id else { return }
        reconnectTask?.cancel()

        let reason = error?.localizedDescription ?? "Stream ended unexpectedly."
        log.error("Playback failure (attempt \(self.reconnectAttempts + 1)): \(reason, privacy: .public)")

        guard reconnectAttempts < Self.maxReconnectAttempts else {
            pause()
            playbackError = "Stream unavailable: \(reason)"
            return
        }

        reconnectAttempts += 1
        let delay = min(2 * pow(2, Double(reconnectAttempts - 1)), 30)
        isBuffering = true
        playbackError = "Connection lost – reconnecting (\(reconnectAttempts)/\(Self.maxReconnectAttempts))…"

        reconnectTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard let self, !Task.isCancelled, self.isPlaying,
                  let station = self.currentStation, station.id == stationID
            else { return }
            self.loadItem(for: station)
            self.player.play()
        }
    }

    private func stopAndClearCurrentStation() {
        pause()
        itemCancellables.removeAll()
        player.replaceCurrentItem(with: nil)
        currentStation = nil
        nowPlaying = NowPlayingMetadata()
        schedulePersist()
    }

    /// Ensures current station/playback remains valid after deletions.
    private func handleDeletedStationIDs(_ ids: [UUID]) {
        guard let currentID = currentStation?.id, ids.contains(currentID) else { return }
        stopAndClearCurrentStation()
        if let first = stations.first {
            selectStation(id: first.id, autoPlay: false)
        }
    }

    /// Creates an AVPlayerItem with stream-friendly HTTP headers and buffering.
    static func makePlayerItem(for url: URL) -> AVPlayerItem {
        let asset = AVURLAsset(
            url: url,
            options: [
                "AVURLAssetHTTPHeaderFieldsKey": ["Icy-MetaData": "1"],
                AVURLAssetHTTPUserAgentKey: AppInfo.userAgent
            ]
        )
        let item = AVPlayerItem(asset: asset)
        item.preferredForwardBufferDuration = 2
        item.canUseNetworkResourcesForLiveStreamingWhilePaused = false
        return item
    }

    private func applyOutputDeviceSelection() {
        let uid = effectiveOutputDeviceUID
        if player.audioOutputDeviceUniqueID != uid {
            player.audioOutputDeviceUniqueID = uid
        }
    }

    // MARK: - Provider metadata polling

    /// Polls provider metadata endpoints when configured for a station.
    private func startMetadataPollingIfNeeded() {
        metadataTask?.cancel()
        metadataTask = nil
        guard
            let urlString = currentStation?.metadataURL,
            let url = URL(string: urlString),
            metadataRefreshSeconds >= 5
        else { return }

        metadataTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.fetchProviderMetadata(from: url)
                let seconds = self?.metadataRefreshSeconds ?? 15
                try? await Task.sleep(for: .seconds(seconds))
            }
        }
    }

    /// Fetches station-specific metadata from a configured provider endpoint.
    private func fetchProviderMetadata(from url: URL) async {
        guard isPlaying else { return }
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 15
            request.setValue(AppInfo.userAgent, forHTTPHeaderField: "User-Agent")
            let (data, _) = try await URLSession.shared.data(for: request)
            guard !Task.isCancelled,
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { return }
            mergeProviderValues(Self.flatten(json: json))
        } catch {
            // Non-fatal: many streams don't provide this endpoint.
        }
    }

    /// Normalizes provider metadata and merges it into now-playing state.
    private func mergeProviderValues(_ values: [String: String]) {
        var updated = nowPlaying
        let oldFingerprint = TrackFingerprint(metadata: nowPlaying)
        var trackIdentityUpdated = false
        let candidateArtist = Self.firstMatch(values, keys: ["artist", "now_playing.song.artist", "song.artist", "current.artist"])
        let candidateTitle = Self.firstMatch(values, keys: ["title", "song", "track", "now_playing.song.title", "song.title", "current.title", "text"])
        let candidateAlbum = Self.firstMatch(values, keys: ["album", "release", "song.album"])
        let candidateYear = Self.firstMatch(values, keys: ["year", "song.year", "release_year"])
        let candidateArtwork = Self.firstMatch(values, keys: ["artwork", "artwork_url", "cover", "cover_url", "image", "image_url", "thumbnail"])

        if let candidateArtist {
            updated.artist = candidateArtist
            trackIdentityUpdated = true
        }
        if let candidateTitle {
            let split = StreamTitleParser.splitArtistTitle(candidateTitle)
            if candidateArtist == nil, let artist = split.artist {
                updated.artist = artist
                updated.title = split.title
            } else {
                updated.title = candidateTitle
            }
            trackIdentityUpdated = true
        }

        if trackIdentityUpdated, TrackFingerprint(metadata: updated) != oldFingerprint {
            resetStaleMetadata(for: &updated)
        }

        if let candidateAlbum {
            updated.album = candidateAlbum
        }
        if let candidateYear {
            updated.year = candidateYear
        }
        if let candidateArtwork, let url = URL(string: candidateArtwork) {
            updated.artworkURL = url
        }

        var extra = values
        for match in [candidateArtist, candidateTitle, candidateAlbum, candidateYear, candidateArtwork] {
            if let match, let key = extra.first(where: { $0.value == match })?.key {
                extra.removeValue(forKey: key)
            }
        }
        // Keep enrichment bookkeeping (it describes the same track).
        for key in NowPlayingMetadata.internalExtraKeys.union(["release_date"]) {
            if let value = updated.extra[key] { extra[key] = value }
        }
        updated.extra = extra
        if updated != nowPlaying {
            nowPlaying = updated
        }
    }

    /// Flattens nested JSON dictionaries into a string map for easy lookup.
    private static func flatten(json: [String: Any], prefix: String = "") -> [String: String] {
        var result: [String: String] = [:]
        for (key, value) in json {
            let normalizedKey = prefix.isEmpty ? key.lowercased() : "\(prefix).\(key.lowercased())"
            if let dict = value as? [String: Any] {
                result.merge(flatten(json: dict, prefix: normalizedKey), uniquingKeysWith: { $1 })
            } else if let array = value as? [Any] {
                result[normalizedKey] = array.map { "\($0)" }.joined(separator: ", ")
            } else if !(value is NSNull) {
                result[normalizedKey] = "\(value)"
            }
        }
        return result
    }

    private static func firstMatch(_ values: [String: String], keys: [String]) -> String? {
        keys.lazy.compactMap { values[$0] }.first { !$0.isEmpty }
    }

    // MARK: - Timed (in-stream) metadata

    /// Applies one batch of timed metadata (ICY/ID3/common keys) as a single update, so that
    /// artist and title arriving in separate items never produce a mixed intermediate track.
    fileprivate func applyTimedMetadata(_ items: [AVMetadataItem]) async {
        var values: [(key: String, value: String)] = []
        var artworkData: Data?

        for item in items {
            let key = (item.commonKey?.rawValue ?? item.key.map { "\($0)" } ?? "").lowercased()
            var string = try? await item.load(.stringValue)
            if string == nil {
                string = (try? await item.load(.value)) as? String
            }
            if let string, !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                values.append((key, string))
            }
            if artworkData == nil, let data = try? await item.load(.dataValue), NSImage(data: data) != nil {
                artworkData = data
            }
        }

        var updated = nowPlaying
        let oldFingerprint = TrackFingerprint(metadata: updated)
        var trackIdentityUpdated = false
        var album: String?
        var year: String?

        func applyTitle(_ raw: String) {
            let split = StreamTitleParser.splitArtistTitle(raw)
            if let artist = split.artist {
                updated.artist = artist
            }
            updated.title = split.title
            trackIdentityUpdated = true
        }

        for (key, value) in values {
            if let icyTitle = StreamTitleParser.icyStreamTitle(in: value) {
                applyTitle(icyTitle)
                continue
            }
            switch key {
            case "title":
                applyTitle(value)
            case "artist":
                updated.artist = value
                trackIdentityUpdated = true
            case "albumname", "album":
                album = value
            case "year":
                year = value
            default:
                if !key.isEmpty, !value.contains("StreamTitle=") {
                    updated.extra[key] = value
                }
            }
        }

        if trackIdentityUpdated, TrackFingerprint(metadata: updated) != oldFingerprint {
            resetStaleMetadata(for: &updated)
        }
        if let album { updated.album = album }
        if let year { updated.year = year }
        if let artworkData, let fileURL = storeEmbeddedArtwork(artworkData) {
            updated.artworkURL = fileURL
        }

        if updated != nowPlaying {
            nowPlaying = updated
        }
    }

    /// Writes in-stream artwork to a temp file (original encoding, previous file removed).
    private func storeEmbeddedArtwork(_ data: Data) -> URL? {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("menubarradio-artwork-\(UUID().uuidString)")
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            return nil
        }
        if let previous = embeddedArtworkFileURL {
            try? FileManager.default.removeItem(at: previous)
        }
        embeddedArtworkFileURL = url
        return url
    }

    // MARK: - Persistence

    /// Coalesces rapid changes (volume slider, typing in the station editor) into one write.
    private func schedulePersist() {
        persistTask?.cancel()
        persistTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            self?.persistNow()
        }
    }

    // MARK: - Enrichment

    /// Debounced enrichment lookup for the current track (year/artwork).
    private func scheduleEnrichment(for fingerprint: TrackFingerprint?) {
        metadataEnrichmentTask?.cancel()
        guard let fingerprint else { return }
        let key = fingerprint.cacheKey
        let alreadyEnriched = nowPlaying.extra["enrichment_key"] == key
            && (nowPlaying.year?.isEmpty == false || nowPlaying.extra["enrichment_source"] != nil)
        guard !alreadyEnriched else { return }

        metadataEnrichmentTask = Task { [weak self, enrichmentService] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            let result = await enrichmentService.enrich(artist: fingerprint.artist, title: fingerprint.title)
            guard let self, !Task.isCancelled, let result else { return }
            guard TrackFingerprint(metadata: self.nowPlaying) == fingerprint else { return }

            var updated = self.nowPlaying
            if updated.album?.isEmpty ?? true {
                updated.album = result.album
            }
            if updated.year?.isEmpty ?? true {
                updated.year = result.year
            }
            if updated.artworkURL == nil {
                updated.artworkURL = result.artworkURL
            }
            updated.extra["enrichment_key"] = key
            updated.extra["enrichment_source"] = result.source
            updated.extra["enrichment_confidence"] = String(format: "%.2f", result.confidence)
            if let releaseDate = result.releaseDate {
                updated.extra["release_date"] = releaseDate
            }
            if let artworkURL = result.artworkURL {
                updated.extra["artwork_source_url"] = artworkURL.absoluteString
            }
            self.nowPlaying = updated
        }
    }

    /// Clears per-track fields when a new song is detected.
    private func resetStaleMetadata(for metadata: inout NowPlayingMetadata) {
        metadata.artworkURL = nil
        metadata.year = nil
        metadata.album = nil
        metadata.extra.removeValue(forKey: "release_date")
        for key in NowPlayingMetadata.internalExtraKeys {
            metadata.extra.removeValue(forKey: key)
        }
    }

    // MARK: - History

    private func recordHistory(for fingerprint: TrackFingerprint?) {
        guard songHistoryLimit > 0 else {
            if !songHistory.isEmpty { songHistory.removeAll() }
            return
        }
        guard let fingerprint else { return }
        let artist = fingerprint.artist
        let title = fingerprint.title

        if Self.isPlaceholder(artist) || Self.isPlaceholder(title) {
            log.debug("Skipping history (placeholder): \(artist) - \(title)")
            return
        }
        if let stationName = currentStation?.name, Self.metadataLooksLikeStationName(artist: artist, title: title, stationName: stationName) {
            log.debug("Skipping history (station ident): \(artist) - \(title)")
            return
        }
        if let last = songHistory.first, last.artist == artist, last.title == title {
            return
        }

        let entry = SongHistoryEntry(
            artist: artist,
            title: title,
            album: nowPlaying.album,
            releaseYear: nowPlaying.releaseYear ?? nowPlaying.year,
            releaseDate: nowPlaying.formattedReleaseDate(),
            stationName: currentStation?.name,
            playedAt: Date()
        )
        log.debug("Adding to history: \(artist) - \(title)")
        songHistory.insert(entry, at: 0)
        trimSongHistory()
    }

    private func trimSongHistory() {
        if songHistory.count > songHistoryLimit {
            songHistory = Array(songHistory.prefix(songHistoryLimit))
        }
    }

    private static let placeholders: Set<String> = [
        "unknown", "unknown artist", "unknown title",
        "no title metadata", "no artist metadata",
        "n/a", "na", "not available",
        "stream", "streaming", "radio", "live",
        "advertisement", "ads", "commercial",
        "verbraucherinformationen", "werbung", "reklame"
    ]

    private static func isPlaceholder(_ value: String) -> Bool {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized.isEmpty || placeholders.contains(normalized) { return true }
        return ["unknown", "no title", "no artist", "advert", "commercial"].contains { normalized.contains($0) }
    }

    /// Detects station idents/jingles that are broadcast as "track" metadata.
    private static func metadataLooksLikeStationName(artist: String, title: String, stationName: String) -> Bool {
        let station = normalizeForComparison(stationName)
        guard !station.isEmpty else { return false }
        if normalizeForComparison(artist).contains(station) || normalizeForComparison(title).contains(station) {
            return true
        }

        let stopwords: Set<String> = ["radio", "fm", "am", "stream", "live", "station", "the"]
        let tokens = stationName
            .lowercased()
            .replacingOccurrences(of: "&", with: "and")
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { $0.count >= 3 && !stopwords.contains($0) }
        guard !tokens.isEmpty else { return false }
        let combined = "\(artist) \(title)".lowercased()
        let matchCount = tokens.filter { combined.contains($0) }.count
        return matchCount >= min(2, tokens.count)
    }

    private static func normalizeForComparison(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: "&", with: "and")
            .filter { $0.isLetter || $0.isNumber }
    }
}

/// Normalized identity for track-change detection and caching.
private struct TrackFingerprint: Equatable {
    let artist: String
    let title: String

    init?(metadata: NowPlayingMetadata) {
        guard
            let artist = metadata.artist?.trimmingCharacters(in: .whitespacesAndNewlines),
            let title = metadata.title?.trimmingCharacters(in: .whitespacesAndNewlines),
            !artist.isEmpty,
            !title.isEmpty
        else {
            return nil
        }
        self.artist = artist
        self.title = title
    }

    var cacheKey: String {
        "\(artist.lowercased())|\(title.lowercased())"
    }
}

extension RadioPlayer: AVPlayerItemMetadataOutputPushDelegate {
    nonisolated func metadataOutput(
        _ output: AVPlayerItemMetadataOutput,
        didOutputTimedMetadataGroups groups: [AVTimedMetadataGroup],
        from track: AVPlayerItemTrack?
    ) {
        // AVMetadataItem is immutable (AVMutableMetadataItem is the mutable subclass, which the
        // metadata output never delivers), so handing the items to the main actor is safe.
        nonisolated(unsafe) let items = groups.flatMap(\.items)
        guard !items.isEmpty else { return }
        Task { @MainActor [weak self] in
            await self?.applyTimedMetadata(items)
        }
    }
}
