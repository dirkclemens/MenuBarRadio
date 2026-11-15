import Foundation
import Testing
@testable import MenuBarRadio

struct TrackMatchingTests {
    @Test func normalizesCaseDiacriticsAndPunctuation() {
        #expect(TrackMatching.normalize("  Beyoncé – Crazy in Love!! ") == "beyonce crazy in love")
        #expect(TrackMatching.normalize("AC/DC") == "ac dc")
        #expect(TrackMatching.normalize("") == "")
    }

    @Test func similarityRanksCloseMatchesHigher() {
        #expect(TrackMatching.similarity("Thunderstruck", "THUNDERSTRUCK") == 1)
        #expect(TrackMatching.similarity("Thunderstruck", "Thunderstruck (Live)") == 0.85)
        #expect(TrackMatching.similarity("Back in Black", "Highway to Hell") == 0)
        #expect(TrackMatching.similarity("", "anything") == 0)
    }

    @Test func scoreIsBoundedAndPrefersExactMatches() {
        let exact = TrackMatching.score(
            candidateArtist: "AC/DC", candidateTitle: "Thunderstruck",
            targetArtist: "AC/DC", targetTitle: "Thunderstruck", providerScore: 100
        )
        let wrong = TrackMatching.score(
            candidateArtist: "Queen", candidateTitle: "Radio Ga Ga",
            targetArtist: "AC/DC", targetTitle: "Thunderstruck", providerScore: 100
        )
        #expect(exact > 0.999)
        #expect(wrong < 0.2)
        #expect(TrackMatching.score(
            candidateArtist: "A", candidateTitle: "B", targetArtist: "A", targetTitle: "B", providerScore: 500
        ) <= 1)
    }

    @Test(arguments: [
        ("1999-05-01", "1999"),
        ("2004", "2004"),
        ("  1987-01 ", "1987"),
    ])
    func extractsYear(date: String, year: String) {
        #expect(TrackMatching.year(fromDate: date) == year)
    }

    @Test func rejectsInvalidYears() {
        #expect(TrackMatching.year(fromDate: nil) == nil)
        #expect(TrackMatching.year(fromDate: "99") == nil)
        #expect(TrackMatching.year(fromDate: "unknown") == nil)
    }

    @Test func escapesLuceneQuotes() {
        #expect(TrackMatching.luceneEscaped(#"12" Mix"#) == #"12\" Mix"#)
        #expect(TrackMatching.luceneEscaped(#"a\b"#) == #"a\\b"#)
    }
}
