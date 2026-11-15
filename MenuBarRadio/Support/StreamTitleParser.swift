import Foundation

/// Pure helpers for turning raw stream metadata strings into artist/title pairs.
nonisolated enum StreamTitleParser {
    /// Separators commonly used between artist and title ("Artist - Title").
    /// Matching the surrounding spaces keeps hyphenated names like "Jay-Z" or "AC-DC" intact.
    private static let separators = [" - ", " – ", " — "]

    /// Splits "Artist - Title" into its parts. Returns `artist == nil` when no separator is found.
    static func splitArtistTitle(_ raw: String) -> (artist: String?, title: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let firstMatch = separators
            .compactMap { trimmed.range(of: $0) }
            .min { $0.lowerBound < $1.lowerBound }

        guard let range = firstMatch else { return (nil, trimmed) }
        let artist = trimmed[..<range.lowerBound].trimmingCharacters(in: .whitespaces)
        let title = trimmed[range.upperBound...].trimmingCharacters(in: .whitespaces)
        guard !artist.isEmpty, !title.isEmpty else { return (nil, trimmed) }
        return (artist, title)
    }

    /// Extracts the value of `StreamTitle='…'` from an ICY metadata block.
    /// Handles blocks with and without the trailing `;`.
    static func icyStreamTitle(in raw: String) -> String? {
        let marker = "StreamTitle='"
        guard let start = raw.range(of: marker)?.upperBound else { return nil }
        let rest = raw[start...]
        let end = rest.range(of: "';")?.lowerBound
            ?? rest.range(of: "'", options: .backwards)?.lowerBound
            ?? rest.endIndex
        let value = rest[..<end].trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
