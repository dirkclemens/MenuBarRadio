import AVFoundation
import Combine
import Foundation

/// Search parameters for directory providers.
struct RadioDirectorySearchQuery {
    var text: String = ""        
    var countryCode: String = "" // https://en.wikipedia.org/wiki/ISO_3166-1_alpha-2
    var tag: String = ""
    var limit: Int = 40
    var hideBroken: Bool = true
}

/// Normalized directory station result.
/* example response from Radio Browser API:
{
  "changeuuid": "4f7e4097-4354-11e8-b74d-52543be04c81",
  "stationuuid": "96062a7b-0601-11e8-ae97-52543be04c81",
  "name": "BBC Radio 1",
  "url": "http://bbcmedia.ic.llnwd.net/stream/bbcmedia_radio1_mf_p",
  "homepage": "http://www.bbc.co.uk/radio1/",
  "tags": "bbc,indie,entertainment,music,rock,pop",
  "country": "United Kingdom",
  "countrycode": "GB",
  "language": "english",
  "codec": "MP3",
  "bitrate": 128
}
*/
struct RadioDirectoryStation: Identifiable, Hashable {
    var id: String { stationUUID }
    let stationUUID: String
    let name: String
    let streamURL: URL?
    let resolvedStreamURL: URL?
    let homepageURL: URL?
    let faviconURL: URL?
    let tags: String
    let country: String
    let countryCode: String // https://en.wikipedia.org/wiki/ISO_3166-1_alpha-2
    let state: String
    let language: String
    let languageCodes: String
    let geoLatitude: Double?
    let geoLongitude: Double?
    let geoDistance: Double?
    let codec: String
    let bitrate: Int?
    let votes: Int?
    let lastCheckOK: Bool

    var preferredStreamURL: URL? {
        if let resolvedStreamURL {
            return resolvedStreamURL
        }
        return streamURL
    }
}

/// Provider interface for station search services.
protocol RadioDirectoryProvider {
    var id: String { get }
    var displayName: String { get }
    func searchStations(query: RadioDirectorySearchQuery) async throws -> [RadioDirectoryStation]
}

/// Provider error types for user-facing feedback.
enum RadioDirectoryError: LocalizedError {
    case invalidRequest
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .invalidRequest:
            return "Could not create a valid search request."
        case .invalidResponse:
            return "Directory provider returned an invalid response."
        }
    }
}

/// Radio Browser provider implementation.
/// The API is served by a pool of community mirrors; the mirror is chosen via
/// `RadioBrowserServerPool` and the next one is tried when a request fails.
struct RadioBrowserDirectoryProvider: RadioDirectoryProvider {
    let id = "radio-browser"
    let displayName = "Radio Browser"
    private let servers: RadioBrowserServerPool

    init(servers: RadioBrowserServerPool = .shared) {
        self.servers = servers
    }

    /// Searches stations via Radio Browser JSON API, failing over between mirrors.
    func searchStations(query: RadioDirectorySearchQuery) async throws -> [RadioDirectoryStation] {
        let hosts = await servers.orderedHosts()
        var lastError: Error = RadioDirectoryError.invalidResponse

        for host in hosts.prefix(RadioBrowserServerPool.maxAttemptsPerRequest) {
            guard let baseURL = URL(string: "https://\(host)") else { continue }
            let request = try Self.makeRequest(query: query, baseURL: baseURL)

            let data: Data
            let statusCode: Int
            do {
                let (body, response) = try await URLSession.shared.data(for: request)
                data = body
                statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            } catch let error as URLError where error.code == .cancelled {
                throw error
            } catch {
                // Transport error (timeout, DNS, TLS): try the next mirror.
                lastError = error
                await servers.markFailed(host)
                continue
            }

            switch statusCode {
            case 200...299:
                do {
                    let stations = try Self.decodeStations(from: data)
                    await servers.markHealthy(host)
                    return stations
                } catch {
                    lastError = error
                    await servers.markFailed(host)
                }
            case 400...499:
                // The request itself is wrong; every mirror would answer the same.
                throw RadioDirectoryError.invalidResponse
            default:
                lastError = RadioDirectoryError.invalidResponse
                await servers.markFailed(host)
            }
        }
        throw lastError
    }

    /// Decodes and normalizes a Radio Browser station list.
    static func decodeStations(from data: Data) throws -> [RadioDirectoryStation] {
        let stations = try JSONDecoder().decode([RadioBrowserStationDTO].self, from: data)
        return stations.compactMap { dto in
            guard !dto.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }

            return RadioDirectoryStation(
                stationUUID: dto.stationuuid,
                name: dto.name,
                streamURL: URL(string: dto.url),
                resolvedStreamURL: URL(string: dto.urlResolved),
                homepageURL: URL(string: dto.homepage),
                faviconURL: URL(string: dto.favicon),
                tags: dto.tags,
                country: dto.country,
                countryCode: dto.countrycode,
                state: dto.state,
                language: dto.language,
                languageCodes: dto.languagecodes,
                geoLatitude: dto.geo_lat,
                geoLongitude: dto.geo_long,
                geoDistance: dto.geo_distance,
                codec: dto.codec,
                bitrate: dto.bitrate,
                votes: dto.votes,
                lastCheckOK: dto.lastcheckok == 1
            )
        }
    }

    /// Builds the Radio Browser query URL for name/tag/country.
    static func makeRequest(query: RadioDirectorySearchQuery, baseURL: URL) throws -> URLRequest {
        let text = query.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let limit = max(1, min(query.limit, 100))
        let hideBroken = query.hideBroken ? "true" : "false"

        let url: URL
        if text.isEmpty {
            var components = URLComponents(url: baseURL.appendingPathComponent("/json/stations/topvote/\(limit)"), resolvingAgainstBaseURL: false)
            components?.queryItems = [
                URLQueryItem(name: "hidebroken", value: hideBroken)
            ]
            guard let resolved = components?.url else { throw RadioDirectoryError.invalidRequest }
            url = resolved
        } else {
            var components = URLComponents(url: baseURL.appendingPathComponent("/json/stations/search"), resolvingAgainstBaseURL: false)
            var queryItems: [URLQueryItem] = [
                URLQueryItem(name: "name", value: text),
                URLQueryItem(name: "limit", value: "\(limit)"),
                URLQueryItem(name: "hidebroken", value: hideBroken),
                URLQueryItem(name: "order", value: "votes"),
                URLQueryItem(name: "reverse", value: "true")
            ]

            let countryCode = query.countryCode.trimmingCharacters(in: .whitespacesAndNewlines)
            if !countryCode.isEmpty {
                queryItems.append(URLQueryItem(name: "countrycode", value: countryCode.uppercased()))
            }

            let tag = query.tag.trimmingCharacters(in: .whitespacesAndNewlines)
            if !tag.isEmpty {
                queryItems.append(URLQueryItem(name: "tag", value: tag))
            }

            components?.queryItems = queryItems
            guard let resolved = components?.url else { throw RadioDirectoryError.invalidRequest }
            url = resolved
        }

        var request = URLRequest(url: url)
        request.setValue(AppInfo.userAgent, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 20
        return request
    }
}

/// Discovers and ranks Radio Browser API mirrors.
///
/// The mirror list is fetched from `all.api.radio-browser.info/json/servers`
/// (cached for a few hours). Mirrors that failed recently are moved to the end,
/// and a working mirror is kept for subsequent requests.
actor RadioBrowserServerPool {
    static let shared = RadioBrowserServerPool()

    /// Used when discovery itself fails.
    static let fallbackHosts = ["de1.api.radio-browser.info", "all.api.radio-browser.info"]
    static let maxAttemptsPerRequest = 3

    private static let discoveryURL = URL(string: "https://all.api.radio-browser.info/json/servers")!
    private let discoveryTTL: TimeInterval = 60 * 60 * 6
    private let failurePenalty: TimeInterval = 60 * 10

    private var hosts: [String] = []
    private var discoveredAt: Date?
    private var preferredHost: String?
    private var failedAt: [String: Date] = [:]

    /// Mirrors in the order they should be tried.
    func orderedHosts() async -> [String] {
        if hosts.isEmpty || discoveredAt.map({ Date().timeIntervalSince($0) > discoveryTTL }) ?? true {
            await discover()
        }
        let now = Date()
        let candidates = hosts.isEmpty ? Self.fallbackHosts : hosts
        return Self.rank(candidates, preferred: preferredHost, failedAt: failedAt, now: now, penalty: failurePenalty)
    }

    func markHealthy(_ host: String) {
        preferredHost = host
        failedAt[host] = nil
    }

    func markFailed(_ host: String) {
        failedAt[host] = Date()
        if preferredHost == host {
            preferredHost = nil
        }
    }

    private func discover() async {
        var request = URLRequest(url: Self.discoveryURL)
        request.timeoutInterval = 10
        request.setValue(AppInfo.userAgent, forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse).map({ (200...299).contains($0.statusCode) }) ?? false
        else {
            // Keep the previous list (or the fallback) and retry on a later search.
            return
        }
        let discovered = Self.hostNames(fromServerList: data)
        guard !discovered.isEmpty else { return }
        hosts = discovered.shuffled()
        discoveredAt = Date()
        if let preferredHost, !discovered.contains(preferredHost) {
            self.preferredHost = nil
        }
    }

    /// Extracts unique API host names from a `/json/servers` response.
    nonisolated static func hostNames(fromServerList data: Data) -> [String] {
        nonisolated struct Server: Decodable { let name: String }
        guard let servers = try? JSONDecoder().decode([Server].self, from: data) else { return [] }
        var seen = Set<String>()
        return servers
            .map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { $0.hasSuffix(".radio-browser.info") && seen.insert($0).inserted }
    }

    /// Orders hosts: last working mirror first, recently failed mirrors last.
    nonisolated static func rank(
        _ hosts: [String],
        preferred: String?,
        failedAt: [String: Date],
        now: Date,
        penalty: TimeInterval
    ) -> [String] {
        func recentlyFailed(_ host: String) -> Bool {
            failedAt[host].map { now.timeIntervalSince($0) < penalty } ?? false
        }
        var healthy = hosts.filter { !recentlyFailed($0) }
        let failed = hosts.filter(recentlyFailed)
        if let preferred, let index = healthy.firstIndex(of: preferred) {
            healthy.insert(healthy.remove(at: index), at: 0)
        }
        return healthy + failed
    }
}

/// View model for directory search + preview playback.
@MainActor
final class RadioDirectoryController: ObservableObject {
    @Published var queryText = ""
    @Published var queryCountryCode = ""
    @Published var queryTag = ""
    @Published var isSearching = false
    @Published var results: [RadioDirectoryStation] = []
    @Published var errorMessage: String?
    @Published var previewingStationID: String?
    @Published var previewVolume: Float = 0.8 {
        didSet { previewPlayer.volume = previewVolume }
    }
    /// Output device for pre-listening (mirrors the main player's selection).
    var outputDeviceUID: String? {
        didSet { previewPlayer.audioOutputDeviceUniqueID = outputDeviceUID }
    }

    let providerName: String

    private let provider: any RadioDirectoryProvider
    private let previewPlayer = AVPlayer()
    private var previewStatusObserver: AnyCancellable?
    private var previewStallCheck: Task<Void, Never>?

    init(provider: any RadioDirectoryProvider) {
        self.provider = provider
        self.providerName = provider.displayName
        previewPlayer.volume = previewVolume
    }

    /// Executes a search with the current query fields.
    func search() async {
        isSearching = true
        errorMessage = nil
        defer { isSearching = false }

        do {
            let query = RadioDirectorySearchQuery(
                text: queryText,
                countryCode: queryCountryCode,
                tag: queryTag
            )
            results = try await provider.searchStations(query: query)
        } catch {
            results = []
            errorMessage = "Search failed: \(error.localizedDescription)"
        }
    }

    /// Starts/stops pre-listen playback for a station.
    func togglePreview(for station: RadioDirectoryStation) {
        if previewingStationID == station.id {
            stopPreview()
            return
        }

        guard let url = station.preferredStreamURL else {
            errorMessage = "No playable stream URL available for this station."
            return
        }

        let item = RadioPlayer.makePlayerItem(for: url)
        errorMessage = nil
        previewStatusObserver = item.publisher(for: \.status)
            .filter { $0 == .failed }
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak item] _ in
                self?.errorMessage = "Preview failed: \(item?.error?.localizedDescription ?? "Unknown stream error")"
                self?.stopPreview()
            }
        previewPlayer.replaceCurrentItem(with: item)
        previewPlayer.isMuted = false
        previewPlayer.volume = previewVolume
        previewPlayer.playImmediately(atRate: 1.0)
        previewingStationID = station.id

        previewStallCheck?.cancel()
        previewStallCheck = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard let self, !Task.isCancelled, self.previewingStationID == station.id else { return }
            if self.previewPlayer.timeControlStatus != .playing {
                self.errorMessage = "Preview stalled: stream may be unavailable."
            }
        }
    }

    /// Stops any active preview playback.
    func stopPreview() {
        previewPlayer.pause()
        previewPlayer.replaceCurrentItem(with: nil)
        previewingStationID = nil
        previewStatusObserver = nil
        previewStallCheck?.cancel()
        previewStallCheck = nil
    }
}

private struct RadioBrowserStationDTO: Decodable {
    let stationuuid: String
    let name: String
    let url: String
    let urlResolved: String
    let homepage: String
    let favicon: String
    let tags: String
    let country: String
    let countrycode: String
    let state: String
    let language: String
    let languagecodes: String
    let geo_lat: Double?
    let geo_long: Double?
    let geo_distance: Double?
    let codec: String
    let bitrate: Int?
    let votes: Int?
    let lastcheckok: Int

    enum CodingKeys: String, CodingKey {
        case stationuuid
        case name
        case url
        case urlResolved = "url_resolved"
        case homepage
        case favicon
        case tags
        case country
        case countrycode
        case state
        case language
        case languagecodes
        case geo_lat
        case geo_long
        case geo_distance
        case codec
        case bitrate
        case votes
        case lastcheckok
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        stationuuid = try container.decode(String.self, forKey: .stationuuid)
        name = (try? container.decode(String.self, forKey: .name)) ?? ""
        url = (try? container.decode(String.self, forKey: .url)) ?? ""
        urlResolved = (try? container.decode(String.self, forKey: .urlResolved)) ?? ""
        homepage = (try? container.decode(String.self, forKey: .homepage)) ?? ""
        favicon = (try? container.decode(String.self, forKey: .favicon)) ?? ""
        tags = (try? container.decode(String.self, forKey: .tags)) ?? ""
        country = (try? container.decode(String.self, forKey: .country)) ?? ""
        countrycode = (try? container.decode(String.self, forKey: .countrycode)) ?? ""
        state = (try? container.decode(String.self, forKey: .state)) ?? ""
        language = (try? container.decode(String.self, forKey: .language)) ?? ""
        languagecodes = (try? container.decode(String.self, forKey: .languagecodes)) ?? ""
        geo_lat = container.decodeDoubleLike(forKey: .geo_lat)
        geo_long = container.decodeDoubleLike(forKey: .geo_long)
        geo_distance = container.decodeDoubleLike(forKey: .geo_distance)
        codec = (try? container.decode(String.self, forKey: .codec)) ?? ""
        bitrate = container.decodeIntLike(forKey: .bitrate)
        votes = container.decodeIntLike(forKey: .votes)
        lastcheckok = container.decodeIntLike(forKey: .lastcheckok) ?? 0
    }
}

private extension KeyedDecodingContainer {
    func decodeIntLike(forKey key: Key) -> Int? {
        if let intValue = try? decode(Int.self, forKey: key) {
            return intValue
        }
        if let stringValue = try? decode(String.self, forKey: key) {
            return Int(stringValue)
        }
        if let boolValue = try? decode(Bool.self, forKey: key) {
            return boolValue ? 1 : 0
        }
        return nil
    }

    func decodeDoubleLike(forKey key: Key) -> Double? {
        if let doubleValue = try? decode(Double.self, forKey: key) {
            return doubleValue
        }
        if let intValue = try? decode(Int.self, forKey: key) {
            return Double(intValue)
        }
        if let stringValue = try? decode(String.self, forKey: key) {
            return Double(stringValue)
        }
        return nil
    }
}
