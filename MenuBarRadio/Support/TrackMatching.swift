import Foundation

/// Pure helpers for matching lookup candidates against the track currently on air.
nonisolated enum TrackMatching {
    /// Combines provider score with fuzzy artist/title similarity (0...1).
    static func score(
        candidateArtist: String,
        candidateTitle: String,
        targetArtist: String,
        targetTitle: String,
        providerScore: Double
    ) -> Double {
        let artistScore = similarity(candidateArtist, targetArtist)
        let titleScore = similarity(candidateTitle, targetTitle)
        let provider = min(max(providerScore / 100, 0), 1)
        return min(1, (titleScore * 0.5) + (artistScore * 0.35) + (provider * 0.15))
    }

    /// Simple token overlap similarity for matching candidates (0...1).
    static func similarity(_ lhs: String, _ rhs: String) -> Double {
        let a = normalize(lhs)
        let b = normalize(rhs)
        guard !a.isEmpty, !b.isEmpty else { return 0 }
        if a == b { return 1 }
        if a.contains(b) || b.contains(a) { return 0.85 }

        let aTokens = Set(a.split(separator: " ").map(String.init))
        let bTokens = Set(b.split(separator: " ").map(String.init))
        let intersect = aTokens.intersection(bTokens).count
        let maxCount = max(aTokens.count, bTokens.count)
        guard maxCount > 0 else { return 0 }
        return Double(intersect) / Double(maxCount)
    }

    /// Normalizes strings for fuzzy matching (case/diacritic/punctuation).
    static func normalize(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .replacingOccurrences(of: "[^a-zA-Z0-9 ]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    /// Extracts the year from a date string such as "1999-05-01" or "1999".
    static func year(fromDate value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 4 else { return nil }
        let year = String(trimmed.prefix(4))
        return Int(year) != nil ? year : nil
    }

    /// Escapes characters with special meaning inside a quoted MusicBrainz Lucene phrase.
    static func luceneEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
