import SwiftUI

/// Now-playing metadata panel (title/artist/release/etc).
struct MetadataView: View {
    @EnvironmentObject private var player: RadioPlayer

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ArtworkView(metadata: player.nowPlaying)
            VStack(alignment: .leading, spacing: 4) {
                Text(player.nowPlaying.title ?? "No title metadata")
                    .font(.headline)
                    .lineLimit(2)
                if let album = player.nowPlaying.album, !album.isEmpty {
                    Text("Album: \(player.nowPlaying.album ?? "No album metadata")")
                        .font(.subheadline)
                        .lineLimit(2)
                }
                Text(player.nowPlaying.artist ?? "Unknown artist")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                
                if let releaseDate = player.nowPlaying.formattedReleaseDate() {
                    Text("Release: \(releaseDate)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if let year = player.nowPlaying.year {
                    Text("Year: \(year)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                HStack(spacing: 10) {
                    if let bitrate = player.currentStation?.bitrate {
                        Text("Bitrate: \(bitrate) kbps")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let codec = player.currentStation?.codec, !codec.isEmpty {
                        Text("Codec: \(codec)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let votes = player.currentStation?.votes {
                        Text("Votes: \(votes)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if let station = player.currentStation {
                    Text(station.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .textSelection(.enabled)
            Spacer(minLength: 0)
        }
    }
}
