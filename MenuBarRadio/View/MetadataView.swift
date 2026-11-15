import SwiftUI

/// Now-playing metadata panel (title/artist/release/etc).
struct MetadataView: View {
    @EnvironmentObject private var player: RadioPlayer
    @State private var isShowingLyrics = false
    @State private var lyricsState: LyricsState = .idle

    var body: some View {
        
        let extraLines = player.nowPlaying.displayExtraLines

        HStack(alignment: .top, spacing: 12) {
            ArtworkView(metadata: player.nowPlaying)
            VStack(alignment: .leading, spacing: 4) {
                Text(player.nowPlaying.title ?? "No title metadata")
                    .font(.headline)
                    .lineLimit(2)
                Text(player.nowPlaying.artist ?? "Unknown artist")
                    .font(.subheadline)
                    .bold()
                    .lineLimit(1)
                if let album = player.nowPlaying.album, !album.isEmpty {
                    Text("Album: \(album)")
                        .font(.subheadline)
                        .lineLimit(2)
                }
                
                HStack(spacing: 8) {
                    if let releaseDate = player.nowPlaying.formattedReleaseDate() {
                        Text("Release: \(releaseDate)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if let year = player.nowPlaying.year {
                        Text("Year: \(year)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Divider().frame(height: 1).background(.windowBackground)
                
                if let station = player.currentStation {
                    let label = station.name.isEmpty ? "Unknown Station" : "Station: \(station.name)"
                    if let url = station.homepageURL ?? URL(string: station.streamURL) {
                        Link(label, destination: url)
                            .font(.caption)
                            .multilineTextAlignment(.leading)
                            .foregroundColor(.blue)
                    } else {
                        Text(label)
                            .font(.caption)
                    }
                }
                if let error = player.playbackError {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .lineLimit(2)
                }
                if let tags = player.currentStation?.tags, !tags.isEmpty {
                    Text("Tags: \(tags)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
                
                HStack{
                    Button("Lyrics") {
                        isShowingLyrics = true
                        loadLyrics()
                    }
                    .font(.caption)
                    .foregroundColor(.blue)
                    .buttonStyle(.link)
                    .disabled(lyricsQuery == nil)
                    .popover(isPresented: $isShowingLyrics, arrowEdge: .top) {
                        lyricsPopover
                    }
                    
                    if let urlString = player.nowPlaying.extra["artwork_source_url"],
                       let url = URL(string: urlString) {
                        Link("| Artwork Source", destination: url)
                            .font(.caption)
                    }
                }
                if let query = searchQuery {
                    HStack {
                        if let url = Self.appleMusicSearchURL(query) {
                            Link("Apple Music", destination: url)
                                .font(.caption)
                        }
                        if let url = Self.spotifySearchURL(query) {
                            Link("Spotify", destination: url)
                                .font(.caption)
                        }
                    }
                }
            }
            .textSelection(.enabled)
            .help(extraLines.joined(separator: "\n"))
//            Spacer(minLength: 0)
        }
    }

    /// "Title Artist" when both are known, used for streaming-service search links.
    private var searchQuery: String? {
        guard let title = lyricsTrackName, let artist = lyricsArtistName else { return nil }
        return "\(title) \(artist)"
    }

    private static func appleMusicSearchURL(_ query: String) -> URL? {
        var components = URLComponents(string: "https://music.apple.com/search")
        components?.queryItems = [URLQueryItem(name: "term", value: query)]
        return components?.url
    }

    private static func spotifySearchURL(_ query: String) -> URL? {
        // Path component: encode everything except unreserved characters (also "/", "&", "?", "#").
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
        return URL(string: "https://open.spotify.com/search/\(encoded)")
    }

    private var lyricsQuery: String? {
        let title = player.nowPlaying.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let artist = player.nowPlaying.artist?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if title.isEmpty && artist.isEmpty { return nil }
        if artist.isEmpty { return title }
        if title.isEmpty { return artist }
        return "\(artist) \(title)"
    }

    private var lyricsTrackName: String? {
        let value = player.nowPlaying.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? nil : value
    }

    private var lyricsArtistName: String? {
        let value = player.nowPlaying.artist?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? nil : value
    }

    private var lyricsPopover: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Lyrics")
                .font(.headline)
            switch lyricsState {
            case .idle, .loading:
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Fetching lyrics…")
                }
            case .loaded(let lyrics):
                ScrollView {
                    Text(lyrics)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
            case .error(let message):
                Text(message)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(width: 320, height: 280)
    }

    private func loadLyrics() {
        guard let query = lyricsQuery else {
            lyricsState = .error("Missing artist or title.")
            return
        }
        lyricsState = .loading
        Task {
            do {
                let results = try await fetchLyrics(query: query, trackName: lyricsTrackName, artistName: lyricsArtistName)
                let lyrics = results
                    .lazy
                    .compactMap { $0.plainLyrics?.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .first { !$0.isEmpty }
                lyricsState = lyrics.map(LyricsState.loaded) ?? .error("No lyrics found.")
            } catch {
                lyricsState = .error("Lyrics lookup failed: \(error.localizedDescription)")
            }
        }
    }
}

private enum LyricsState: Equatable {
    case idle
    case loading
    case loaded(String)
    case error(String)
}
