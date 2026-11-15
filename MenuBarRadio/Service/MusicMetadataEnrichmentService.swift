import Foundation

/// Enriched track metadata used to augment now-playing information.
nonisolated struct TrackEnrichmentResult: Codable, Sendable {
    let artist: String
    let title: String
    let album: String?
    let year: String?
    let releaseDate: String?
    let artworkURL: URL?
    let confidence: Double
    let source: String
}

/// Fetches release year and artwork from free, no-key services with caching.
actor MusicMetadataEnrichmentService {
    private struct CachedValue: Codable {
        /// `nil` = looked up successfully but nothing matched (negative cache).
        let result: TrackEnrichmentResult?
        let expiresAt: Date
    }

    private let session: URLSession
    private let userAgent = "\(AppInfo.userAgent) (radio metadata enrichment)"
    private let cacheTTL: TimeInterval = 60 * 60 * 24 * 30
    /// Misses (jingles, ads, obscure tracks) are retried after a day instead of on every play.
    private let missTTL: TimeInterval = 60 * 60 * 24
    private let maxCacheEntries = 1_000
    private let maxCoverArtReleaseLookups = 3
    private let storageKey = "MenuBarRadio.TrackEnrichmentCache"
    private var cache: [String: CachedValue]
    private var lastRequestAt: Date?

    init(session: URLSession = .shared) {
        self.session = session
        self.cache = Self.loadCache(forKey: storageKey)
    }

    /// Performs a debounced, cached lookup for the given artist/title.
    func enrich(artist: String, title: String) async -> TrackEnrichmentResult? {
        let normalizedArtist = normalize(artist)
        let normalizedTitle = normalize(title)
        guard !normalizedArtist.isEmpty, !normalizedTitle.isEmpty else { return nil }

        let key = cacheKey(artist: normalizedArtist, title: normalizedTitle)
        if let cached = cache[key], cached.expiresAt > Date() {
            return cached.result
        }

        var hadNetworkError = false

        var musicBrainzResult: TrackEnrichmentResult?
        do {
            musicBrainzResult = try await queryMusicBrainz(artist: artist, title: title)
        } catch {
            hadNetworkError = true
        }
        if Task.isCancelled { return nil }

        // iTunes is only needed when MusicBrainz found nothing or has no cover art.
        var iTunesResult: TrackEnrichmentResult?
        if musicBrainzResult?.artworkURL == nil {
            do {
                iTunesResult = try await queryITunes(artist: artist, title: title)
            } catch {
                hadNetworkError = true
            }
        }
        if Task.isCancelled { return nil }

        let result: TrackEnrichmentResult?
        if let mb = musicBrainzResult {
            if mb.artworkURL == nil, let iTunes = iTunesResult, let artwork = iTunes.artworkURL {
                result = TrackEnrichmentResult(
                    artist: mb.artist,
                    title: mb.title,
                    album: mb.album ?? iTunes.album,
                    year: mb.year ?? iTunes.year,
                    releaseDate: mb.releaseDate ?? iTunes.releaseDate,
                    artworkURL: artwork,
                    confidence: mb.confidence,
                    source: "MusicBrainz+iTunesArtwork"
                )
            } else {
                result = mb
            }
        } else {
            result = iTunesResult
        }

        // Don't remember a miss that may only be caused by a network problem.
        if result != nil || !hadNetworkError {
            let ttl = result == nil ? missTTL : cacheTTL
            cache[key] = CachedValue(result: result, expiresAt: Date().addingTimeInterval(ttl))
            saveCache()
        }
        return result
    }

    /// Queries MusicBrainz recordings and optionally resolves cover art.
    /// Throws on transport/HTTP errors, returns `nil` when nothing matches.
    private func queryMusicBrainz(artist: String, title: String) async throws -> TrackEnrichmentResult? {
        let queryString = "recording:\"\(Self.luceneEscaped(title))\" AND artist:\"\(Self.luceneEscaped(artist))\""
        guard var components = URLComponents(string: "https://musicbrainz.org/ws/2/recording/") else { return nil }
        components.queryItems = [
            URLQueryItem(name: "query", value: queryString),
            URLQueryItem(name: "fmt", value: "json"),
            URLQueryItem(name: "limit", value: "8")
        ]
        guard let url = components.url else { return nil }

        let data = try await fetch(url)
        let payload = try JSONDecoder().decode(MusicBrainzResponse.self, from: data)

        let candidates = payload.recordings.compactMap { recording -> MusicBrainzCandidate? in
            let confidence = scoreCandidate(
                candidateArtist: recording.artistCredit.first?.name ?? "",
                candidateTitle: recording.title,
                targetArtist: artist,
                targetTitle: title,
                providerScore: Double(recording.score ?? "") ?? 0
            )
            guard confidence >= 0.5 else { return nil }
            return MusicBrainzCandidate(recording: recording, confidence: confidence)
        }

        guard let best = candidates.max(by: { $0.confidence < $1.confidence }) else { return nil }
        let artwork = await fetchMusicBrainzArtwork(for: best.recording)
        let date = best.recording.firstReleaseDate
        return TrackEnrichmentResult(
            artist: artist,
            title: title,
            album: best.recording.primaryReleaseTitle ?? best.recording.primaryReleaseGroupTitle,
            year: Self.yearFromDate(date),
            releaseDate: date,
            artworkURL: artwork,
            confidence: best.confidence,
            source: "MusicBrainz"
        )
    }

    /// Queries iTunes Search for release date and artwork.
    /// Throws on transport/HTTP errors, returns `nil` when nothing matches.
    private func queryITunes(artist: String, title: String) async throws -> TrackEnrichmentResult? {
        guard var components = URLComponents(string: "https://itunes.apple.com/search") else { return nil }
        components.queryItems = [
            URLQueryItem(name: "term", value: "\(artist) \(title)"),
            URLQueryItem(name: "entity", value: "song"),
            URLQueryItem(name: "limit", value: "10")
        ]
        guard let url = components.url else { return nil }

        let data = try await fetch(url)
        let payload = try JSONDecoder().decode(ITunesResponse.self, from: data)

        let candidates = payload.results.compactMap { track -> TrackEnrichmentResult? in
            let confidence = scoreCandidate(
                candidateArtist: track.artistName,
                candidateTitle: track.trackName,
                targetArtist: artist,
                targetTitle: title,
                providerScore: 100
            )
            guard confidence >= 0.5 else { return nil }

            return TrackEnrichmentResult(
                artist: artist,
                title: title,
                album: track.collectionName,
                year: Self.yearFromDate(track.releaseDate),
                releaseDate: track.releaseDate,
                artworkURL: track.bestArtworkURL,
                confidence: confidence,
                source: "iTunes"
            )
        }

        return candidates.max(by: { $0.confidence < $1.confidence })
    }

    /// Rate-limited GET with the app's User-Agent; throws for non-2xx responses.
    private func fetch(_ url: URL) async throws -> Data {
        try await throttleRequests()
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return data
    }

    /// Attempts to resolve Cover Art Archive artwork for a recording.
    private func fetchMusicBrainzArtwork(for recording: MusicBrainzRecording) async -> URL? {
        if let releaseID = recording.releases?.compactMap(\.id).first,
           let coverURL = await fetchCoverArtArchiveURL(releaseID: releaseID) {
            return coverURL
        }

        guard let lookupURL = URL(string: "https://musicbrainz.org/ws/2/recording/\(recording.id)?inc=releases&fmt=json"),
              let data = try? await fetch(lookupURL),
              let lookup = try? JSONDecoder().decode(MusicBrainzRecordingLookupResponse.self, from: data)
        else { return nil }

        // Each lookup is rate-limited to ~1/s, so only try the first few releases.
        for release in lookup.releases.prefix(maxCoverArtReleaseLookups) {
            if Task.isCancelled { return nil }
            if let cover = await fetchCoverArtArchiveURL(releaseID: release.id) {
                return cover
            }
        }
        return nil
    }

    /// Resolves a release ID into a cover art URL (404 = release has no artwork).
    private func fetchCoverArtArchiveURL(releaseID: String) async -> URL? {
        guard let url = URL(string: "https://coverartarchive.org/release/\(releaseID)"),
              let data = try? await fetch(url),
              let payload = try? JSONDecoder().decode(CoverArtArchiveResponse.self, from: data),
              let front = payload.images.first(where: { $0.front == true })
        else { return nil }
        return front.thumbnails?.large ?? front.thumbnails?.small ?? front.image
    }

    /// Enforces ~1 request/second for free API compliance.
    private func throttleRequests() async throws {
        if let lastRequestAt {
            let delta = Date().timeIntervalSince(lastRequestAt)
            if delta < 1 {
                try await Task.sleep(for: .seconds(1 - delta))
            }
        }
        lastRequestAt = Date()
    }

    /// Combines provider score with fuzzy artist/title similarity.
    private func scoreCandidate(
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

    /// Simple token overlap similarity for matching candidates.
    private func similarity(_ lhs: String, _ rhs: String) -> Double {
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
    private func normalize(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .replacingOccurrences(of: "[^a-zA-Z0-9 ]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private func cacheKey(artist: String, title: String) -> String {
        "\(artist)|\(title)"
    }

    private static func yearFromDate(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 4 else { return nil }
        let year = String(trimmed.prefix(4))
        return Int(year) != nil ? year : nil
    }

    /// Escapes characters with special meaning in MusicBrainz' Lucene query syntax.
    private static func luceneEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static func loadCache(forKey key: String) -> [String: CachedValue] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([String: CachedValue].self, from: data)
        else { return [:] }
        let now = Date()
        return decoded.filter { $0.value.expiresAt > now }
    }

    /// Persists the cache, dropping expired entries and capping its size so
    /// UserDefaults doesn't grow without bound.
    private func saveCache() {
        let now = Date()
        cache = cache.filter { $0.value.expiresAt > now }
        if cache.count > maxCacheEntries {
            let keep = cache.sorted { $0.value.expiresAt > $1.value.expiresAt }.prefix(maxCacheEntries)
            cache = Dictionary(uniqueKeysWithValues: keep.map { ($0.key, $0.value) })
        }
        guard let data = try? JSONEncoder().encode(cache) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}

nonisolated private struct MusicBrainzCandidate {
    let recording: MusicBrainzRecording
    let confidence: Double
}

nonisolated private struct MusicBrainzResponse: Decodable {
    let recordings: [MusicBrainzRecording]
}

nonisolated private struct MusicBrainzRecording: Decodable {
    let id: String
    let title: String
    let score: String?
    let firstReleaseDate: String?
    let artistCredit: [MusicBrainzArtistCredit]
    let releases: [MusicBrainzRelease]?
    let releaseGroups: [MusicBrainzReleaseGroup]?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case score
        case firstReleaseDate = "first-release-date"
        case artistCredit = "artist-credit"
        case releases
        case releaseGroups = "release-groups"
    }

    var primaryReleaseTitle: String? {
        releases?.first?.title
    }

    var primaryReleaseGroupTitle: String? {
        releaseGroups?.first?.title
    }
}

nonisolated private struct MusicBrainzArtistCredit: Decodable {
    let name: String
}

nonisolated private struct MusicBrainzRelease: Decodable {
    let id: String
    let title: String?
}

nonisolated private struct MusicBrainzReleaseGroup: Decodable {
    let title: String?
}

nonisolated private struct MusicBrainzRecordingLookupResponse: Decodable {
    let releases: [MusicBrainzRelease]
}

nonisolated private struct ITunesResponse: Decodable {
    let results: [ITunesTrack]
}

nonisolated private struct ITunesTrack: Decodable {
    let artistName: String
    let trackName: String
    let collectionName: String?
    let releaseDate: String?
    let artworkUrl100: String?

    var bestArtworkURL: URL? {
        guard let artworkUrl100 else { return nil }
        let upscaled = artworkUrl100.replacingOccurrences(of: "100x100bb", with: "600x600bb")
        return URL(string: upscaled) ?? URL(string: artworkUrl100)
    }
}

nonisolated private struct CoverArtArchiveResponse: Decodable {
    let images: [CoverArtArchiveImage]
}

nonisolated private struct CoverArtArchiveImage: Decodable {
    let front: Bool?
    let image: URL?
    let thumbnails: CoverArtArchiveThumbnails?
}

nonisolated private struct CoverArtArchiveThumbnails: Decodable {
    let small: URL?
    let large: URL?
}
