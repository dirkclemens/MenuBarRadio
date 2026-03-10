import SwiftUI

/// Floating artwork window content with basic playback controls.
struct ArtworkPopupView: View {
    @EnvironmentObject private var player: RadioPlayer
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            artwork
            VStack(spacing: 4) {
                Text(player.nowPlaying.title ?? "No title metadata")
                    .font(.headline)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    Text(player.nowPlaying.artist ?? "Unknown artist")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if let album = player.nowPlaying.album, !album.isEmpty {
                        Text(player.nowPlaying.album ?? "No album metadata")
                            .font(.subheadline)
                            .lineLimit(1)
                    }
                }
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
            HStack(spacing: 12) {
                Button {
                    player.togglePlayPause()
                } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .frame(width: 26)
                }
                .buttonStyle(.borderedProminent)

                Spacer()
                
                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark.circle")
                        .frame(width: 26)
                }
            }
        }
        .padding(16)
//        .background(.foreground)
        .frame(minWidth: 320, minHeight: 380)
    }

    private var artwork: some View {
        Group {
            if let url = player.nowPlaying.artworkURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
//        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .frame(minWidth: 220, minHeight: 260)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var placeholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(.quaternary)
            Image(systemName: "music.note")
                .foregroundStyle(.secondary)
        }
    }
}
