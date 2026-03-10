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
    let language: String
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
struct RadioBrowserDirectoryProvider: RadioDirectoryProvider {
    let id = "radio-browser"
    let displayName = "Radio Browser"
    private let baseURL = URL(string: "https://de1.api.radio-browser.info")!
    private let userAgent = "MenuBarRadio/1.0"

    /// Searches stations via Radio Browser JSON API.
    func searchStations(query: RadioDirectorySearchQuery) async throws -> [RadioDirectoryStation] {
        let request = try makeRequest(query: query)
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw RadioDirectoryError.invalidResponse
        }

        let decoder = JSONDecoder()
        let stations = try decoder.decode([RadioBrowserStationDTO].self, from: data)
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
                language: dto.language,
                codec: dto.codec,
                bitrate: dto.bitrate,
                votes: dto.votes,
                lastCheckOK: dto.lastcheckok == 1
            )
        }
    }

    /// Builds the Radio Browser query URL for name/tag/country.
    private func makeRequest(query: RadioDirectorySearchQuery) throws -> URLRequest {
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
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 20
        return request
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

    let providerName: String

    private let provider: any RadioDirectoryProvider
    private let previewPlayer = AVPlayer()
    private var previewStatusObserver: NSKeyValueObservation?

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

        let item = makePreviewItem(for: url)
        previewStatusObserver?.invalidate()
        previewStatusObserver = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            guard let self else { return }
            if item.status == .failed {
                Task { @MainActor in
                    self.errorMessage = "Preview failed: \(item.error?.localizedDescription ?? "Unknown stream error")"
                    self.stopPreview()
                }
            }
        }
        previewPlayer.replaceCurrentItem(with: item)
        previewPlayer.isMuted = false
        previewPlayer.volume = previewVolume
        previewPlayer.playImmediately(atRate: 1.0)
        previewingStationID = station.id

        Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard self.previewingStationID == station.id else { return }
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
        previewStatusObserver?.invalidate()
        previewStatusObserver = nil
    }

    /// Builds a preview item with stream-friendly headers.
    private func makePreviewItem(for url: URL) -> AVPlayerItem {
        let headers = [
            "User-Agent": "MenuBarRadio/1.0",
            "Icy-MetaData": "1"
        ]
        let asset = AVURLAsset(
            url: url,
            options: [
                "AVURLAssetHTTPHeaderFieldsKey": headers,
                "AVURLAssetHTTPUserAgentKey": "MenuBarRadio/1.0"
            ]
        )
        let item = AVPlayerItem(asset: asset)
        item.preferredForwardBufferDuration = 2
        item.canUseNetworkResourcesForLiveStreamingWhilePaused = false
        return item
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
    let language: String
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
        case language
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
        language = (try? container.decode(String.self, forKey: .language)) ?? ""
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
}
