import Foundation
import Testing
@testable import MenuBarRadio

struct AppSettingsTests {
    private func decode(_ json: String) throws -> AppSettings {
        try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
    }

    @Test func migratesSettingsFromVersion102() throws {
        let settings = try decode("""
        {"stations":[{"id":"7E1D9F1C-0000-4000-8000-000000000001","name":"A","streamURL":"https://a","isFavorite":true},
                     {"name":"Imported without id","streamURL":"http://b"}],
         "selectedStationID":"7E1D9F1C-0000-4000-8000-000000000001",
         "menuBarDisplay":{"showArtist":false,"showTitle":true,"showYear":true,"showStationNameFallback":true},
         "volume":0.5,"metadataRefreshSeconds":20,"autoPlayOnLaunch":true,"restoreArtworkPopupOnLaunch":false,
         "selectedOutputDeviceID":73,"showDockIcon":true,"songHistoryLimit":12,"songHistory":[],"recordTracks":false}
        """)

        #expect(settings.stations.map(\.name) == ["A", "Imported without id"])
        #expect(settings.stations[0].isFavorite)
        #expect(settings.stations[1].isFavorite == false)
        #expect(settings.menuBarDisplay.showArtist == false)
        #expect(settings.menuBarDisplay.maxLength == 36)
        #expect(settings.volume == 0.5)
        #expect(settings.legacyOutputDeviceID == 73)
        #expect(settings.selectedOutputDeviceUID == nil)
        #expect(settings.showDockIcon)
        #expect(settings.songHistoryLimit == 12)
    }

    @Test func invalidFieldFallsBackWithoutLosingStations() throws {
        let settings = try decode(#"{"stations":[{"name":"X","streamURL":"u"}],"volume":"loud"}"#)
        #expect(settings.stations.count == 1)
        #expect(settings.volume == 0.8)
    }

    @Test func emptyObjectDecodesToDefaults() throws {
        let settings = try decode("{}")
        #expect(settings.stations.map(\.name) == AppSettings.defaults.stations.map(\.name))
        #expect(settings.volume == AppSettings.defaults.volume)
        #expect(settings.selectedOutputDeviceUID == nil)
    }

    @Test func encodingDropsLegacyDeviceID() throws {
        var settings = try decode(#"{"stations":[],"selectedOutputDeviceID":73}"#)
        settings.selectedOutputDeviceUID = "BuiltInSpeakerDevice"

        let json = try #require(String(data: JSONEncoder().encode(settings), encoding: .utf8))
        #expect(!json.contains("selectedOutputDeviceID"))
        #expect(json.contains("BuiltInSpeakerDevice"))

        let roundTrip = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
        #expect(roundTrip.selectedOutputDeviceUID == "BuiltInSpeakerDevice")
        #expect(roundTrip.legacyOutputDeviceID == nil)
    }

    @Test func stationWithoutRequiredFieldsFailsToDecode() {
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(RadioStation.self, from: Data(#"{"name":"No URL"}"#.utf8))
        }
    }

    @Test func displayExtraLinesHideInternalKeys() {
        let metadata = NowPlayingMetadata(extra: [
            "genre": "Rock",
            "enrichment_source": "MusicBrainz",
            "artwork_source_url": "https://example.com/a.jpg",
            "bitrate": "128",
        ])
        #expect(metadata.displayExtraLines == ["bitrate: 128", "genre: Rock"])
    }
}
