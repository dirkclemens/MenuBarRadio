import Foundation

/// Release date helpers for localized display and year extraction.
extension NowPlayingMetadata {
    /// Returns a localized release date string when present.
    func formattedReleaseDate() -> String? {
        guard let raw = extra["release_date"]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty
        else { return nil }

        if let date = ReleaseDateFormatters.parseISODate(raw) {
            return ReleaseDateFormatters.output.string(from: date)
        }
        return raw
    }

    /// Returns a release year derived from release_date, falling back to year.
    var releaseYear: String? {
        if let raw = extra["release_date"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !raw.isEmpty,
           let date = ReleaseDateFormatters.parseISODate(raw) {
            return ReleaseDateFormatters.year.string(from: date)
        }
        return year
    }
}

private enum ReleaseDateFormatters {
    static func parseISODate(_ value: String) -> Date? {
        if let date = iso8601Full.date(from: value) {
            return date
        }
        if let date = iso8601NoFraction.date(from: value) {
            return date
        }
        if let date = iso8601NoTime.date(from: value) {
            return date
        }
        return nil
    }

    static let iso8601Full: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static let iso8601NoFraction: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static let iso8601NoTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static let output: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    static let year: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy"
        return formatter
    }()
}
