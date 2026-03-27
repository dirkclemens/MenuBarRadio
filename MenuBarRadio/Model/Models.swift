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
    var selectedOutputDeviceID: UInt32
    var showDockIcon: Bool
    var songHistoryLimit: Int
    var songHistory: [SongHistoryEntry]
    var recordTracks: Bool

    enum CodingKeys: String, CodingKey {
        case stations
        case selectedStationID
        case menuBarDisplay
        case volume
        case metadataRefreshSeconds
        case autoPlayOnLaunch
        case restoreArtworkPopupOnLaunch
        case selectedOutputDeviceID
        case showDockIcon
        case songHistoryLimit
        case songHistory
        case recordTracks
    }

    init(
        stations: [RadioStation],
        selectedStationID: UUID?,
        menuBarDisplay: MenuBarDisplayConfiguration,
        volume: Float,
        metadataRefreshSeconds: Double,
        autoPlayOnLaunch: Bool,
        restoreArtworkPopupOnLaunch: Bool,
        selectedOutputDeviceID: UInt32,
        showDockIcon: Bool,
        songHistoryLimit: Int,
        songHistory: [SongHistoryEntry],
        recordTracks: Bool
    ) {
        self.stations = stations
        self.selectedStationID = selectedStationID
        self.menuBarDisplay = menuBarDisplay
        self.volume = volume
        self.metadataRefreshSeconds = metadataRefreshSeconds
        self.autoPlayOnLaunch = autoPlayOnLaunch
        self.restoreArtworkPopupOnLaunch = restoreArtworkPopupOnLaunch
        self.selectedOutputDeviceID = selectedOutputDeviceID
        self.showDockIcon = showDockIcon
        self.songHistoryLimit = songHistoryLimit
        self.songHistory = songHistory
        self.recordTracks = recordTracks
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        stations = try container.decode([RadioStation].self, forKey: .stations)
        selectedStationID = try container.decodeIfPresent(UUID.self, forKey: .selectedStationID)
        menuBarDisplay = try container.decode(MenuBarDisplayConfiguration.self, forKey: .menuBarDisplay)
        volume = try container.decode(Float.self, forKey: .volume)
        metadataRefreshSeconds = try container.decode(Double.self, forKey: .metadataRefreshSeconds)
        autoPlayOnLaunch = try container.decodeIfPresent(Bool.self, forKey: .autoPlayOnLaunch) ?? false
        restoreArtworkPopupOnLaunch = try container.decodeIfPresent(Bool.self, forKey: .restoreArtworkPopupOnLaunch) ?? false
        selectedOutputDeviceID = try container.decodeIfPresent(UInt32.self, forKey: .selectedOutputDeviceID) ?? 0
        showDockIcon = try container.decodeIfPresent(Bool.self, forKey: .showDockIcon) ?? false
        songHistoryLimit = try container.decodeIfPresent(Int.self, forKey: .songHistoryLimit) ?? 10
        songHistory = try container.decodeIfPresent([SongHistoryEntry].self, forKey: .songHistory) ?? []
        recordTracks = try container.decodeIfPresent(Bool.self, forKey: .recordTracks) ?? false
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
        selectedOutputDeviceID: 0,
        showDockIcon: false,
        songHistoryLimit: 10,
        songHistory: [],
        recordTracks: false
    )
}
