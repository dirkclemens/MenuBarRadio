import SwiftUI

/// Now-playing metadata panel (title/artist/release/etc).
struct MetadataView: View {
    @EnvironmentObject private var player: RadioPlayer
    @State private var isShowingLyrics = false
    @State private var lyricsState: LyricsState = .idle

    var body: some View {
        
        let extraLines = player.nowPlaying.extra.sorted(by: { $0.key < $1.key }).map { "\($0.key): \($0.value)" }
        
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
                    Text("Album: \(player.nowPlaying.album ?? "No album metadata")")
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
                    let url = URL(string: station.streamURL)!
                    Link(station.name.isEmpty ? "Unknown Station" : "Station: \(station.name)", destination: url)
                        .font(.caption)
                        .multilineTextAlignment(.leading)
                        .frame(alignment: .leading)
                        .foregroundColor(.blue)
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
                HStack{
                    if let title = player.nowPlaying.title,
                       let artist = player.nowPlaying.artist {

                        let query = "\(title) \(artist)"
                        let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""

                        // For Apple Music, we can just do a search query with the title and artist combined.
                        Link("Apple Music", destination: URL(string: "https://music.apple.com/search?term=\(encodedQuery)")!)
                            .font(.caption)

                        // For Spotify, we can just do a search query with the title and artist combined.
                        let url = URL(string: "https://open.spotify.com/search/\(encodedQuery)") ?? URL(string: "https://open.spotify.com")!
                        Link("Spotify", destination: url)
                            .font(.caption)
                    }
                }
            }
            .textSelection(.enabled)
            .help(extraLines.joined(separator: "\n"))
//            Spacer(minLength: 0)
        }
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
        NSLog("Lyrics lookup start: \(query)")
        lyricsState = .loading
        Task {
            do {
                let results = try await fetchLyrics(query: query, trackName: lyricsTrackName, artistName: lyricsArtistName)
                NSLog("Lyrics lookup results: \(results.count)")
                let best = results.first { ($0.plainLyrics?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false) }
                let lyrics = best?.plainLyrics?.trimmingCharacters(in: .whitespacesAndNewlines)
                await MainActor.run {
                    if let lyrics, !lyrics.isEmpty {
                        lyricsState = .loaded(lyrics)
                    } else {
                        lyricsState = .error("No lyrics found.")
                    }
                }
            } catch {
                NSLog("Lyrics lookup failed: \(error.localizedDescription)")
                await MainActor.run {
                    lyricsState = .error("Lyrics lookup failed.")
                }
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
