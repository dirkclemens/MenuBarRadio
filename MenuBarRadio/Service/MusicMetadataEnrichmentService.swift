import Foundation

struct TrackEnrichmentResult: Codable {
    let artist: String
    let title: String
    let year: String?
    let releaseDate: String?
    let artworkURL: URL?
    let confidence: Double
    let source: String
}

actor MusicMetadataEnrichmentService {
    private struct CachedValue: Codable {
        let result: TrackEnrichmentResult
        let expiresAt: Date
    }

    private let session: URLSession
    private let userAgent = "MenuBarRadio/1.0 (radio metadata enrichment)"
    private let cacheTTL: TimeInterval = 60 * 60 * 24 * 30
    private let storageKey = "MenuBarRadio.TrackEnrichmentCache"
    private var cache: [String: CachedValue]
    private var lastRequestAt: Date?

    init(session: URLSession = .shared) {
        self.session = session
        self.cache = Self.loadCache(forKey: storageKey)
    }

    func enrich(artist: String, title: String) async -> TrackEnrichmentResult? {
        let normalizedArtist = normalize(artist)
        let normalizedTitle = normalize(title)
        guard !normalizedArtist.isEmpty, !normalizedTitle.isEmpty else { return nil }

        let key = cacheKey(artist: normalizedArtist, title: normalizedTitle)
        if let cached = cache[key], cached.expiresAt > Date() {
            return cached.result
        }

        let musicBrainzResult = await queryMusicBrainz(artist: artist, title: title)
        let iTunesResult = await queryITunes(artist: artist, title: title)

        if var result = musicBrainzResult {
            if result.artworkURL == nil, let iTunesArtwork = iTunesResult?.artworkURL {
                result = TrackEnrichmentResult(
                    artist: result.artist,
                    title: result.title,
                    year: result.year ?? iTunesResult?.year,
                    releaseDate: result.releaseDate ?? iTunesResult?.releaseDate,
                    artworkURL: iTunesArtwork,
                    confidence: result.confidence,
                    source: "MusicBrainz+iTunesArtwork"
                )
            }
            cache[key] = CachedValue(result: result, expiresAt: Date().addingTimeInterval(cacheTTL))
            saveCache()
            return result
        }

        if let result = iTunesResult {
            cache[key] = CachedValue(result: result, expiresAt: Date().addingTimeInterval(cacheTTL))
            saveCache()
            return result
        }

        return nil
    }

    private func queryMusicBrainz(artist: String, title: String) async -> TrackEnrichmentResult? {
        let queryString = "recording:\"\(title)\" AND artist:\"\(artist)\""
        guard var components = URLComponents(string: "https://musicbrainz.org/ws/2/recording/") else { return nil }
        components.queryItems = [
            URLQueryItem(name: "query", value: queryString),
            URLQueryItem(name: "fmt", value: "json"),
            URLQueryItem(name: "limit", value: "8")
        ]
        guard let url = components.url else { return nil }

        do {
            try await throttleRequests()
            var request = URLRequest(url: url)
            request.timeoutInterval = 20
            request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else { return nil }
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
                year: Self.yearFromDate(date),
                releaseDate: date,
                artworkURL: artwork,
                confidence: best.confidence,
                source: "MusicBrainz"
            )
        } catch {
            return nil
        }
    }

    private func queryITunes(artist: String, title: String) async -> TrackEnrichmentResult? {
        guard var components = URLComponents(string: "https://itunes.apple.com/search") else { return nil }
        components.queryItems = [
            URLQueryItem(name: "term", value: "\(artist) \(title)"),
            URLQueryItem(name: "entity", value: "song"),
            URLQueryItem(name: "limit", value: "10")
        ]
        guard let url = components.url else { return nil }

        do {
            try await throttleRequests()
            var request = URLRequest(url: url)
            request.timeoutInterval = 20
            request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else { return nil }
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
                    year: Self.yearFromDate(track.releaseDate),
                    releaseDate: track.releaseDate,
                    artworkURL: track.bestArtworkURL,
                    confidence: confidence,
                    source: "iTunes"
                )
            }

            return candidates.max(by: { $0.confidence < $1.confidence })
        } catch {
            return nil
        }
    }

    private func fetchMusicBrainzArtwork(for recording: MusicBrainzRecording) async -> URL? {
        if let releaseID = recording.releases?.compactMap(\.id).first,
           let coverURL = await fetchCoverArtArchiveURL(releaseID: releaseID) {
            return coverURL
        }

        guard let lookupURL = URL(string: "https://musicbrainz.org/ws/2/recording/\(recording.id)?inc=releases&fmt=json") else { return nil }
        do {
            try await throttleRequests()
            var request = URLRequest(url: lookupURL)
            request.timeoutInterval = 20
            request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else { return nil }
            let lookup = try JSONDecoder().decode(MusicBrainzRecordingLookupResponse.self, from: data)
            for release in lookup.releases {
                if let cover = await fetchCoverArtArchiveURL(releaseID: release.id) {
                    return cover
                }
            }
        } catch {
            return nil
        }
        return nil
    }

    private func fetchCoverArtArchiveURL(releaseID: String) async -> URL? {
        guard let url = URL(string: "https://coverartarchive.org/release/\(releaseID)") else { return nil }
        do {
            try await throttleRequests()
            var request = URLRequest(url: url)
            request.timeoutInterval = 20
            request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else { return nil }
            let payload = try JSONDecoder().decode(CoverArtArchiveResponse.self, from: data)
            if let front = payload.images.first(where: { $0.front == true }) {
                return front.thumbnails?.large ?? front.thumbnails?.small ?? front.image
            }
        } catch {
            return nil
        }
        return nil
    }

    private func throttleRequests() async throws {
        if let lastRequestAt {
            let delta = Date().timeIntervalSince(lastRequestAt)
            if delta < 1 {
                let delay = UInt64((1 - delta) * 1_000_000_000)
                try await Task.sleep(nanoseconds: delay)
            }
        }
        lastRequestAt = Date()
    }

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

    private static func loadCache(forKey key: String) -> [String: CachedValue] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [:] }
        let decoded = try? JSONDecoder().decode([String: CachedValue].self, from: data)
        return decoded ?? [:]
    }

    private func saveCache() {
        guard let data = try? JSONEncoder().encode(cache) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}

private struct MusicBrainzCandidate {
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

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case score
        case firstReleaseDate = "first-release-date"
        case artistCredit = "artist-credit"
        case releases
    }
}

nonisolated private struct MusicBrainzArtistCredit: Decodable {
    let name: String
}

nonisolated private struct MusicBrainzRelease: Decodable {
    let id: String
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
