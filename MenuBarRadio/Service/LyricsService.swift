//
//  LyricsService.swift
//  MenuBarRadio
//

import Foundation
import Combine

struct LyricsResponse: Decodable {
    let trackName: String
    let artistName: String
    let plainLyrics: String?

    enum CodingKeys: String, CodingKey {
        case trackName
        case artistName
        case plainLyrics
        case track_name
        case artist_name
        case plain_lyrics
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        trackName = (try? container.decode(String.self, forKey: .trackName))
            ?? (try? container.decode(String.self, forKey: .track_name))
            ?? ""
        artistName = (try? container.decode(String.self, forKey: .artistName))
            ?? (try? container.decode(String.self, forKey: .artist_name))
            ?? ""
        plainLyrics = (try? container.decode(String.self, forKey: .plainLyrics))
            ?? (try? container.decode(String.self, forKey: .plain_lyrics))
    }
}

func fetchLyrics(query: String, trackName: String? = nil, artistName: String? = nil) async throws -> [LyricsResponse] {
    let baseURL = URL(string: "https://lrclib.net/api/search")!
    var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
    var items: [URLQueryItem] = []

    let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
    if !trimmedQuery.isEmpty {
        items.append(URLQueryItem(name: "q", value: trimmedQuery))
    }
    if let trackName, !trackName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        items.append(URLQueryItem(name: "track_name", value: trackName))
    }
    if let artistName, !artistName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        items.append(URLQueryItem(name: "artist_name", value: artistName))
    }

    components?.queryItems = items.isEmpty ? nil : items
    guard let url = components?.url else { return [] }

    var request = URLRequest(url: url)
    request.setValue("MenuBarRadio/1.0", forHTTPHeaderField: "User-Agent")
    let (data, _) = try await URLSession.shared.data(for: request)
    return try JSONDecoder().decode([LyricsResponse].self, from: data)
}
