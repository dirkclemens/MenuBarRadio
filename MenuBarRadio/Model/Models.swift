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

    init(
        id: UUID = UUID(),
        name: String,
        streamURL: String,
        metadataURL: String? = nil,
        isFavorite: Bool = false,
        codec: String? = nil,
        bitrate: Int? = nil,
        votes: Int? = nil
    ) {
        self.id = id
        self.name = name
        self.streamURL = streamURL
        self.metadataURL = metadataURL
        self.isFavorite = isFavorite
        self.codec = codec
        self.bitrate = bitrate
        self.votes = votes
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

    enum CodingKeys: String, CodingKey {
        case stations
        case selectedStationID
        case menuBarDisplay
        case volume
        case metadataRefreshSeconds
        case autoPlayOnLaunch
    }

    init(
        stations: [RadioStation],
        selectedStationID: UUID?,
        menuBarDisplay: MenuBarDisplayConfiguration,
        volume: Float,
        metadataRefreshSeconds: Double,
        autoPlayOnLaunch: Bool
    ) {
        self.stations = stations
        self.selectedStationID = selectedStationID
        self.menuBarDisplay = menuBarDisplay
        self.volume = volume
        self.metadataRefreshSeconds = metadataRefreshSeconds
        self.autoPlayOnLaunch = autoPlayOnLaunch
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        stations = try container.decode([RadioStation].self, forKey: .stations)
        selectedStationID = try container.decodeIfPresent(UUID.self, forKey: .selectedStationID)
        menuBarDisplay = try container.decode(MenuBarDisplayConfiguration.self, forKey: .menuBarDisplay)
        volume = try container.decode(Float.self, forKey: .volume)
        metadataRefreshSeconds = try container.decode(Double.self, forKey: .metadataRefreshSeconds)
        autoPlayOnLaunch = try container.decodeIfPresent(Bool.self, forKey: .autoPlayOnLaunch) ?? false
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
        autoPlayOnLaunch: false
    )
}
