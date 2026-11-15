import Foundation

/// A user-configured radio station entry.
struct RadioStation: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var streamURL: String
    var metadataURL: String?
    var isFavorite: Bool
    var codec: String?
    var bitrate: Int?
    var votes: Int?
    var tags: String?
    var country: String?
    var countryCode: String?
    var state: String?
    var language: String?
    var languageCodes: String?
    var homepageURL: URL?
    var faviconURL: URL?
    var geoLatitude: Double?
    var geoLongitude: Double?
    var geoDistance: Double?

    init(
        id: UUID = UUID(),
        name: String,
        streamURL: String,
        metadataURL: String? = nil,
        isFavorite: Bool = false,
        codec: String? = nil,
        bitrate: Int? = nil,
        votes: Int? = nil,
        tags: String? = nil,
        country: String? = nil,
        countryCode: String? = nil,
        state: String? = nil,
        language: String? = nil,
        languageCodes: String? = nil,
        homepageURL: URL? = nil,
        faviconURL: URL? = nil,
        geoLatitude: Double? = nil,
        geoLongitude: Double? = nil,
        geoDistance: Double? = nil
    ) {
        self.id = id
        self.name = name
        self.streamURL = streamURL
        self.metadataURL = metadataURL
        self.isFavorite = isFavorite
        self.codec = codec
        self.bitrate = bitrate
        self.votes = votes
        self.tags = tags
        self.country = country
        self.countryCode = countryCode
        self.state = state
        self.language = language
        self.languageCodes = languageCodes
        self.homepageURL = homepageURL
        self.faviconURL = faviconURL
        self.geoLatitude = geoLatitude
        self.geoLongitude = geoLongitude
        self.geoDistance = geoDistance
    }
}

extension RadioStation {
    /// Lenient decoding: only `name` and `streamURL` are required, so hand-written
    /// or older JSON imports (without `id`/`isFavorite`) still load.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID(),
            name: try c.decode(String.self, forKey: .name),
            streamURL: try c.decode(String.self, forKey: .streamURL),
            metadataURL: try? c.decodeIfPresent(String.self, forKey: .metadataURL),
            isFavorite: (try? c.decodeIfPresent(Bool.self, forKey: .isFavorite)) ?? false,
            codec: try? c.decodeIfPresent(String.self, forKey: .codec),
            bitrate: try? c.decodeIfPresent(Int.self, forKey: .bitrate),
            votes: try? c.decodeIfPresent(Int.self, forKey: .votes),
            tags: try? c.decodeIfPresent(String.self, forKey: .tags),
            country: try? c.decodeIfPresent(String.self, forKey: .country),
            countryCode: try? c.decodeIfPresent(String.self, forKey: .countryCode),
            state: try? c.decodeIfPresent(String.self, forKey: .state),
            language: try? c.decodeIfPresent(String.self, forKey: .language),
            languageCodes: try? c.decodeIfPresent(String.self, forKey: .languageCodes),
            homepageURL: try? c.decodeIfPresent(URL.self, forKey: .homepageURL),
            faviconURL: try? c.decodeIfPresent(URL.self, forKey: .faviconURL),
            geoLatitude: try? c.decodeIfPresent(Double.self, forKey: .geoLatitude),
            geoLongitude: try? c.decodeIfPresent(Double.self, forKey: .geoLongitude),
            geoDistance: try? c.decodeIfPresent(Double.self, forKey: .geoDistance)
        )
    }
}

/// Live now-playing metadata derived from streams and enrichment services.
struct NowPlayingMetadata: Codable, Equatable {
    var artist: String?
    var title: String?
    var album: String?
    var year: String?
    var artworkURL: URL?
    var extra: [String: String]

    init(
        artist: String? = nil,
        title: String? = nil,
        album: String? = nil,
        year: String? = nil,
        artworkURL: URL? = nil,
        extra: [String: String] = [:]
    ) {
        self.artist = artist
        self.title = title
        self.album = album
        self.year = year
        self.artworkURL = artworkURL
        self.extra = extra
    }

    /// Keys in `extra` that are used for internal bookkeeping and not meant for display.
    static let internalExtraKeys: Set<String> = [
        "enrichment_key", "enrichment_source", "enrichment_confidence", "artwork_source_url"
    ]

    /// User-facing `key: value` lines from `extra`, sorted by key.
    var displayExtraLines: [String] {
        extra
            .filter { !Self.internalExtraKeys.contains($0.key) }
            .sorted { $0.key < $1.key }
            .map { "\($0.key): \($0.value)" }
    }
}

/// Snapshot of a recently played track for history display.
struct SongHistoryEntry: Identifiable, Codable, Equatable {
    var id: UUID
    var artist: String
    var title: String
    var album: String?
    var releaseYear: String?
    var releaseDate: String?
    var stationName: String?
    var playedAt: Date

    init(
        id: UUID = UUID(),
        artist: String,
        title: String,
        album: String? = nil,
        releaseYear: String? = nil,
        releaseDate: String? = nil,
        stationName: String? = nil,
        playedAt: Date = Date()
    ) {
        self.id = id
        self.artist = artist
        self.title = title
        self.album = album
        self.releaseYear = releaseYear
        self.releaseDate = releaseDate
        self.stationName = stationName
        self.playedAt = playedAt
    }
}

/// Controls which fields appear in the menu bar label.
struct MenuBarDisplayConfiguration: Codable, Equatable {
    var showArtist: Bool = true
    var showTitle: Bool = true
    var showYear: Bool = false
    var showStationNameFallback: Bool = true
    var maxLength: Int = 36

    init() {}

    /// Lenient decoding so that adding new options never invalidates stored settings.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        showArtist = (try? c.decodeIfPresent(Bool.self, forKey: .showArtist)) ?? true
        showTitle = (try? c.decodeIfPresent(Bool.self, forKey: .showTitle)) ?? true
        showYear = (try? c.decodeIfPresent(Bool.self, forKey: .showYear)) ?? false
        showStationNameFallback = (try? c.decodeIfPresent(Bool.self, forKey: .showStationNameFallback)) ?? true
        maxLength = (try? c.decodeIfPresent(Int.self, forKey: .maxLength)) ?? 36
    }
}

/// Persisted app settings stored in UserDefaults.
struct AppSettings: Codable {
    var stations: [RadioStation]
    var selectedStationID: UUID?
    var menuBarDisplay: MenuBarDisplayConfiguration
    var volume: Float
    var metadataRefreshSeconds: Double
    var autoPlayOnLaunch: Bool
    var restoreArtworkPopupOnLaunch: Bool
    /// CoreAudio device UID (stable across reboots/reconnects). `nil` = system default.
    var selectedOutputDeviceUID: String?
    /// Legacy numeric CoreAudio device ID from versions ≤ 1.0.2, read only for migration.
    var legacyOutputDeviceID: UInt32?
    var showDockIcon: Bool
    var songHistoryLimit: Int
    var songHistory: [SongHistoryEntry]

    enum CodingKeys: String, CodingKey {
        case stations
        case selectedStationID
        case menuBarDisplay
        case volume
        case metadataRefreshSeconds
        case autoPlayOnLaunch
        case restoreArtworkPopupOnLaunch
        case selectedOutputDeviceUID
        case selectedOutputDeviceID
        case showDockIcon
        case songHistoryLimit
        case songHistory
    }

    init(
        stations: [RadioStation],
        selectedStationID: UUID?,
        menuBarDisplay: MenuBarDisplayConfiguration,
        volume: Float,
        metadataRefreshSeconds: Double,
        autoPlayOnLaunch: Bool,
        restoreArtworkPopupOnLaunch: Bool,
        selectedOutputDeviceUID: String?,
        showDockIcon: Bool,
        songHistoryLimit: Int,
        songHistory: [SongHistoryEntry]
    ) {
        self.stations = stations
        self.selectedStationID = selectedStationID
        self.menuBarDisplay = menuBarDisplay
        self.volume = volume
        self.metadataRefreshSeconds = metadataRefreshSeconds
        self.autoPlayOnLaunch = autoPlayOnLaunch
        self.restoreArtworkPopupOnLaunch = restoreArtworkPopupOnLaunch
        self.selectedOutputDeviceUID = selectedOutputDeviceUID
        self.legacyOutputDeviceID = nil
        self.showDockIcon = showDockIcon
        self.songHistoryLimit = songHistoryLimit
        self.songHistory = songHistory
    }

    /// Every field falls back to its default, so a single malformed or newly added
    /// value never discards the user's station list.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings.defaults
        stations = (try? c.decodeIfPresent([RadioStation].self, forKey: .stations)) ?? d.stations
        selectedStationID = try? c.decodeIfPresent(UUID.self, forKey: .selectedStationID)
        menuBarDisplay = (try? c.decodeIfPresent(MenuBarDisplayConfiguration.self, forKey: .menuBarDisplay)) ?? d.menuBarDisplay
        volume = (try? c.decodeIfPresent(Float.self, forKey: .volume)) ?? d.volume
        metadataRefreshSeconds = (try? c.decodeIfPresent(Double.self, forKey: .metadataRefreshSeconds)) ?? d.metadataRefreshSeconds
        autoPlayOnLaunch = (try? c.decodeIfPresent(Bool.self, forKey: .autoPlayOnLaunch)) ?? d.autoPlayOnLaunch
        restoreArtworkPopupOnLaunch = (try? c.decodeIfPresent(Bool.self, forKey: .restoreArtworkPopupOnLaunch)) ?? d.restoreArtworkPopupOnLaunch
        selectedOutputDeviceUID = try? c.decodeIfPresent(String.self, forKey: .selectedOutputDeviceUID)
        legacyOutputDeviceID = try? c.decodeIfPresent(UInt32.self, forKey: .selectedOutputDeviceID)
        showDockIcon = (try? c.decodeIfPresent(Bool.self, forKey: .showDockIcon)) ?? d.showDockIcon
        songHistoryLimit = (try? c.decodeIfPresent(Int.self, forKey: .songHistoryLimit)) ?? d.songHistoryLimit
        songHistory = (try? c.decodeIfPresent([SongHistoryEntry].self, forKey: .songHistory)) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(stations, forKey: .stations)
        try c.encodeIfPresent(selectedStationID, forKey: .selectedStationID)
        try c.encode(menuBarDisplay, forKey: .menuBarDisplay)
        try c.encode(volume, forKey: .volume)
        try c.encode(metadataRefreshSeconds, forKey: .metadataRefreshSeconds)
        try c.encode(autoPlayOnLaunch, forKey: .autoPlayOnLaunch)
        try c.encode(restoreArtworkPopupOnLaunch, forKey: .restoreArtworkPopupOnLaunch)
        try c.encodeIfPresent(selectedOutputDeviceUID, forKey: .selectedOutputDeviceUID)
        try c.encode(showDockIcon, forKey: .showDockIcon)
        try c.encode(songHistoryLimit, forKey: .songHistoryLimit)
        try c.encode(songHistory, forKey: .songHistory)
    }

    static let defaults = AppSettings(
        stations: [
            RadioStation(name: "XTRA FM AAC", streamURL: "https://playerservices.streamtheworld.com/api/livestream-redirect/XTRAFMAAC.aac", isFavorite: true),
            RadioStation(name: "Radio BOB Rockparty", streamURL: "http://streams.radiobob.de/rockparty/mp3-192/mediaplayer"),
            RadioStation(name: "KROQ FM AAC", streamURL: "https://playerservices.streamtheworld.com/api/livestream-redirect/KROQFMAAC.aac")
        ],
        selectedStationID: nil,
        menuBarDisplay: MenuBarDisplayConfiguration(),
        volume: 0.8,
        metadataRefreshSeconds: 15,
        autoPlayOnLaunch: false,
        restoreArtworkPopupOnLaunch: false,
        selectedOutputDeviceUID: nil,
        showDockIcon: false,
        songHistoryLimit: 10,
        songHistory: []
    )
}
