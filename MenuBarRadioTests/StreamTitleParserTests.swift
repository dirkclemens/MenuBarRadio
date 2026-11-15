import Foundation
import Testing
@testable import MenuBarRadio

struct StreamTitleParserTests {
    @Test(arguments: [
        ("Jay-Z - Empire State of Mind", "Jay-Z", "Empire State of Mind"),
        ("AC/DC – Thunderstruck", "AC/DC", "Thunderstruck"),
        ("Queen — Bohemian Rhapsody", "Queen", "Bohemian Rhapsody"),
        ("  Daft Punk - Around the World  ", "Daft Punk", "Around the World"),
        ("Guns N' Roses - Sweet Child O' Mine - Live", "Guns N' Roses", "Sweet Child O' Mine - Live"),
    ])
    func splitsArtistAndTitle(raw: String, artist: String, title: String) {
        let result = StreamTitleParser.splitArtistTitle(raw)
        #expect(result.artist == artist)
        #expect(result.title == title)
    }

    @Test(arguments: ["Radio BOB! Live", "Jay-Z", " - Only Title", "Only Artist - "])
    func keepsTextWithoutSeparatorAsTitle(raw: String) {
        let result = StreamTitleParser.splitArtistTitle(raw)
        #expect(result.artist == nil)
        #expect(result.title == raw.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    @Test func extractsICYStreamTitle() {
        #expect(StreamTitleParser.icyStreamTitle(in: "StreamTitle='A - B';StreamUrl='';") == "A - B")
        #expect(StreamTitleParser.icyStreamTitle(in: "StreamTitle='Guns N' Roses - X'") == "Guns N' Roses - X")
        #expect(StreamTitleParser.icyStreamTitle(in: "StreamTitle='Without terminator") == "Without terminator")
    }

    @Test func ignoresEmptyOrMissingICYTitle() {
        #expect(StreamTitleParser.icyStreamTitle(in: "StreamTitle='';") == nil)
        #expect(StreamTitleParser.icyStreamTitle(in: "StreamUrl='http://x';") == nil)
        #expect(StreamTitleParser.icyStreamTitle(in: "") == nil)
    }
}
