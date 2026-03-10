import AVFoundation
import AppKit
import Combine
import Foundation

/// Core playback engine: stream control, metadata parsing, and settings persistence.
@MainActor
final class RadioPlayer: NSObject, ObservableObject {
    @Published private(set) var isPlaying = false
    @Published private(set) var currentStation: RadioStation?
    @Published private(set) var nowPlaying = NowPlayingMetadata()
    @Published var stations: [RadioStation] {
        didSet { persist() }
    }
    @Published var menuBarDisplay: MenuBarDisplayConfiguration {
        didSet { persist() }
    }
    @Published var volume: Float {
        didSet {
            player.volume = volume
            persist()
        }
    }
    @Published var metadataRefreshSeconds: Double {
        didSet { persist() }
    }
    @Published var autoPlayOnLaunch: Bool {
        didSet { persist() }
    }

    private let settingsStore = SettingsStore()
    private let enrichmentService = MusicMetadataEnrichmentService()
    private let player = AVPlayer()
    private var metadataOutput: AVPlayerItemMetadataOutput?
    private var metadataTask: Task<Void, Never>?
    private var metadataEnrichmentTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    override init() {
        let settings = settingsStore.load()
        self.stations = settings.stations
        self.menuBarDisplay = settings.menuBarDisplay
        self.volume = settings.volume
        self.metadataRefreshSeconds = settings.metadataRefreshSeconds
        self.autoPlayOnLaunch = settings.autoPlayOnLaunch
        super.init()

        player.volume = volume

        let selectedID = settings.selectedStationID ?? stations.first?.id
        if let selectedID {
            selectStation(id: selectedID, autoPlay: autoPlayOnLaunch)
        }

        $nowPlaying
            .map { TrackFingerprint(metadata: $0) }
            .removeDuplicates()
            .sink { [weak self] fingerprint in
                self?.scheduleEnrichment(for: fingerprint)
            }
            .store(in: &cancellables)
    }

    deinit {
        metadataTask?.cancel()
        metadataEnrichmentTask?.cancel()
    }

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
        
        var text: String
        if parts.isEmpty {
            text = menuBarDisplay.showStationNameFallback ? (currentStation?.name ?? "") : "" // "Radio"
        } else {
            text = parts.joined(separator: " • ")
        }

        if text.count > menuBarDisplay.maxLength {
            let clipped = text.prefix(menuBarDisplay.maxLength)
            return String(clipped) + "…"
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
        if !nowPlaying.extra.isEmpty {
            let extraLines = nowPlaying.extra.sorted(by: { $0.key < $1.key }).map { "\($0.key): \($0.value)" }
            lines.append(contentsOf: extraLines.prefix(8))
        }
        return lines.isEmpty ? "Streaming Radio" : lines.joined(separator: "\n")
    }

    func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }

    func play() {
        if player.currentItem == nil, let id = currentStation?.id {
            selectStation(id: id, autoPlay: true)
            return
        }
        player.play()
        isPlaying = true
        startMetadataPollingIfNeeded()
    }

    func pause() {
        player.pause()
        isPlaying = false
        metadataTask?.cancel()
        metadataTask = nil
    }

    /// Switches the player to a given station and optionally starts playback.
    func selectStation(id: UUID, autoPlay: Bool? = nil) {
        guard let station = stations.first(where: { $0.id == id }) else { return }
        currentStation = station
        nowPlaying = NowPlayingMetadata()

        guard let url = URL(string: station.streamURL) else { return }

        let item = makePlayerItem(for: url)
        let output = AVPlayerItemMetadataOutput(identifiers: nil)
        output.setDelegate(self, queue: .main)
        item.add(output)
        metadataOutput = output

        player.replaceCurrentItem(with: item)
        player.volume = volume

        let shouldAutoPlay = autoPlay ?? isPlaying
        if shouldAutoPlay {
            play()
        } else {
            pause()
        }
        persist()
    }

    func addStation() {
        let newStation = RadioStation(name: "New Station", streamURL: "https://")
        stations.append(newStation)
    }

    func appendStation(_ station: RadioStation, makeCurrent: Bool = false, autoPlay: Bool = false) {
        stations.append(station)
        if makeCurrent {
            selectStation(id: station.id, autoPlay: autoPlay)
        }
    }

    func updateStation(_ station: RadioStation) {
        guard let index = stations.firstIndex(where: { $0.id == station.id }) else { return }
        stations[index] = station
        if currentStation?.id == station.id {
            currentStation = station
            if isPlaying {
                selectStation(id: station.id, autoPlay: true)
            }
        }
    }

    func deleteStations(offsets: IndexSet) {
        let ids = offsets.compactMap { stations[$0].id }
        for index in offsets.sorted(by: >) {
            stations.remove(at: index)
        }
        handleDeletedStationIDs(ids)
    }

    func deleteStation(id: UUID) {
        guard let index = stations.firstIndex(where: { $0.id == id }) else { return }
        stations.remove(at: index)
        handleDeletedStationIDs([id])
    }

    /// Replaces the full station list while keeping a valid selection if possible.
    func replaceStations(with newStations: [RadioStation]) {
        stations = newStations

        guard !newStations.isEmpty else {
            currentStation = nil
            player.replaceCurrentItem(with: nil)
            pause()
            return
        }

        if let currentID = currentStation?.id, newStations.contains(where: { $0.id == currentID }) {
            currentStation = newStations.first(where: { $0.id == currentID })
            return
        }

        let wasPlaying = isPlaying
        selectStation(id: newStations[0].id, autoPlay: wasPlaying)
    }

    func toggleFavorite(id: UUID) {
        guard let index = stations.firstIndex(where: { $0.id == id }) else { return }
        stations[index].isFavorite.toggle()
        if currentStation?.id == id {
            currentStation = stations[index]
        }
    }

    /// Polls provider metadata endpoints when configured for a station.
    private func startMetadataPollingIfNeeded() {
        metadataTask?.cancel()
        guard
            let station = currentStation,
            let urlString = station.metadataURL,
            let url = URL(string: urlString),
            metadataRefreshSeconds >= 5
        else { return }

        metadataTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.fetchProviderMetadata(from: url)
                let nanoseconds = UInt64((self?.metadataRefreshSeconds ?? 15) * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanoseconds)
            }
        }
    }

    /// Creates an AVPlayerItem with stream-friendly HTTP headers and buffering.
    private func makePlayerItem(for url: URL) -> AVPlayerItem {
        let headers = [
            "User-Agent": "MenuBarRadio/1.0",
            "Icy-MetaData": "1"
        ]
        let asset = AVURLAsset(
            url: url,
            options: [
                "AVURLAssetHTTPHeaderFieldsKey": headers,
                "AVURLAssetHTTPUserAgentKey": "MenuBarRadio/1.0"
            ]
        )
        let item = AVPlayerItem(asset: asset)
        item.preferredForwardBufferDuration = 2
        item.canUseNetworkResourcesForLiveStreamingWhilePaused = false
        return item
    }

    /// Ensures current station/playback remains valid after deletions.
    private func handleDeletedStationIDs(_ ids: [UUID]) {
        if let currentID = currentStation?.id, ids.contains(currentID) {
            currentStation = nil
            player.replaceCurrentItem(with: nil)
            pause()
            if let first = stations.first {
                selectStation(id: first.id)
            }
        }
    }

    /// Fetches station-specific metadata from a configured provider endpoint.
    private func fetchProviderMetadata(from url: URL) async {
        guard isPlaying else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
            let flattened = flatten(json: json)
            mergeProviderValues(flattened)
        } catch {
            // Non-fatal: many streams don't provide this endpoint.
        }
    }

    /// Normalizes provider metadata and merges it into now-playing state.
    private func mergeProviderValues(_ values: [String: String]) {
        var updated = nowPlaying
        let oldFingerprint = TrackFingerprint(metadata: nowPlaying)
        var trackIdentityUpdated = false
        let candidateArtist = firstMatch(values, keys: ["artist", "now_playing.song.artist", "song.artist", "current.artist"])
        let candidateTitle = firstMatch(values, keys: ["title", "song", "track", "now_playing.song.title", "song.title", "current.title", "text"])
        let candidateAlbum = firstMatch(values, keys: ["album", "release", "song.album"])
        let candidateYear = firstMatch(values, keys: ["year", "song.year", "release_year"])
        let candidateArtwork = firstMatch(values, keys: ["artwork", "artwork_url", "cover", "cover_url", "image", "image_url", "thumbnail"])

        if let candidateArtist {
            updated.artist = candidateArtist
            trackIdentityUpdated = true
        }
        if let candidateTitle {
            if updated.artist == nil, candidateTitle.contains(" - ") {
                let parts = candidateTitle.split(separator: "-", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                if parts.count == 2 {
                    updated.artist = parts[0]
                    updated.title = parts[1]
                    trackIdentityUpdated = true
                } else {
                    updated.title = candidateTitle
                    trackIdentityUpdated = true
                }
            } else {
                updated.title = candidateTitle
                trackIdentityUpdated = true
            }
        }

        if trackIdentityUpdated {
            let newFingerprint = TrackFingerprint(metadata: updated)
            if newFingerprint != oldFingerprint {
                resetStaleMetadata(for: &updated)
            }
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
        [candidateArtist, candidateTitle, candidateAlbum, candidateYear, candidateArtwork].forEach { match in
            if let match, let key = extra.first(where: { $0.value == match })?.key {
                extra.removeValue(forKey: key)
            }
        }
        updated.extra = extra
        nowPlaying = updated
    }

    /// Flattens nested JSON dictionaries into a string map for easy lookup.
    private func flatten(json: [String: Any], prefix: String = "") -> [String: String] {
        var result: [String: String] = [:]
        for (key, value) in json {
            let normalizedKey = prefix.isEmpty ? key.lowercased() : "\(prefix).\(key.lowercased())"
            if let dict = value as? [String: Any] {
                result.merge(flatten(json: dict, prefix: normalizedKey), uniquingKeysWith: { $1 })
            } else if let array = value as? [Any] {
                let joined = array.map { "\($0)" }.joined(separator: ", ")
                result[normalizedKey] = joined
            } else {
                result[normalizedKey] = "\(value)"
            }
        }
        return result
    }

    private func firstMatch(_ values: [String: String], keys: [String]) -> String? {
        for key in keys {
            if let value = values[key], !value.isEmpty {
                return value
            }
        }
        return nil
    }

    /// Parses timed metadata (ICY/ID3/common keys) from the stream.
    private func updateFromTimedMetadata(item: AVMetadataItem) {
        var updated = nowPlaying
        let oldFingerprint = TrackFingerprint(metadata: nowPlaying)
        var trackIdentityUpdated = false

        let stringValue = item.stringValue ?? item.value as? String
        if let stringValue {
            let normalizedKey = (item.commonKey?.rawValue ?? "\(String(describing: item.key))").lowercased()

            switch normalizedKey {
            case "title":
                if stringValue.contains("StreamTitle='") {
                    parseICYTitle(stringValue, into: &updated)
                    trackIdentityUpdated = true
                } else if stringValue.contains(" - ") {
                    let parts = stringValue.split(separator: "-", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                    if parts.count == 2 {
                        updated.artist = parts[0]
                        updated.title = parts[1]
                        trackIdentityUpdated = true
                    } else {
                        updated.title = stringValue
                        trackIdentityUpdated = true
                    }
                } else {
                    updated.title = stringValue
                    trackIdentityUpdated = true
                }
            case "artist":
                updated.artist = stringValue
                trackIdentityUpdated = true
            case "albumname", "album":
                updated.album = stringValue
            case "year":
                updated.year = stringValue
            default:
                if stringValue.contains("StreamTitle='") {
                    parseICYTitle(stringValue, into: &updated)
                    trackIdentityUpdated = true
                } else {
                    updated.extra[normalizedKey] = stringValue
                }
            }
        }

        if trackIdentityUpdated {
            let newFingerprint = TrackFingerprint(metadata: updated)
            if newFingerprint != oldFingerprint {
                resetStaleMetadata(for: &updated)
            }
        }

        if let data = item.dataValue, let image = NSImage(data: data), let tiff = image.tiffRepresentation {
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("menubarradio-artwork-\(UUID().uuidString).tiff")
            try? tiff.write(to: tempURL)
            updated.artworkURL = tempURL
        }

        nowPlaying = updated
    }

    /// Extracts artist/title from ICY StreamTitle patterns.
    private func parseICYTitle(_ raw: String, into metadata: inout NowPlayingMetadata) {
        let marker = "StreamTitle='"
        guard let start = raw.range(of: marker)?.upperBound else { return }
        guard let end = raw[start...].range(of: "';")?.lowerBound else { return }
        let titleBlock = String(raw[start..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
        if titleBlock.contains(" - ") {
            let parts = titleBlock.split(separator: "-", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count == 2 {
                metadata.artist = parts[0]
                metadata.title = parts[1]
                return
            }
        }
        metadata.title = titleBlock
    }

    private func persist() {
        settingsStore.save(
            AppSettings(
                stations: stations,
                selectedStationID: currentStation?.id,
                menuBarDisplay: menuBarDisplay,
                volume: volume,
                metadataRefreshSeconds: metadataRefreshSeconds,
                autoPlayOnLaunch: autoPlayOnLaunch
            )
        )
    }

    /// Debounced enrichment lookup for the current track (year/artwork).
    private func scheduleEnrichment(for fingerprint: TrackFingerprint?) {
        metadataEnrichmentTask?.cancel()
        guard let fingerprint else { return }
        let key = fingerprint.cacheKey
        let alreadyEnriched = nowPlaying.extra["enrichment_key"] == key && (nowPlaying.year?.isEmpty == false || nowPlaying.extra["enrichment_source"] != nil)
        guard !alreadyEnriched else { return }

        metadataEnrichmentTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard let self else { return }
            let result = await enrichmentService.enrich(artist: fingerprint.artist, title: fingerprint.title)
            guard !Task.isCancelled else { return }
            guard let result else { return }

            await MainActor.run {
                let current = TrackFingerprint(metadata: self.nowPlaying)
                guard current == fingerprint else { return }

                var updated = self.nowPlaying
                if updated.album == nil || updated.album?.isEmpty == true {
                    updated.album = result.album
                }
                if updated.year == nil || updated.year?.isEmpty == true {
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
    }

    /// Clears per-track fields when a new song is detected.
    private func resetStaleMetadata(for metadata: inout NowPlayingMetadata) {
        metadata.artworkURL = nil
        metadata.year = nil
        metadata.album = nil
        metadata.extra.removeValue(forKey: "release_date")
        metadata.extra.removeValue(forKey: "artwork_source_url")
        metadata.extra.removeValue(forKey: "enrichment_source")
        metadata.extra.removeValue(forKey: "enrichment_confidence")
        metadata.extra.removeValue(forKey: "enrichment_key")
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
        Task { @MainActor [weak self] in
            guard let self else { return }
            for group in groups {
                for item in group.items {
                    updateFromTimedMetadata(item: item)
                }
            }
        }
    }
}
