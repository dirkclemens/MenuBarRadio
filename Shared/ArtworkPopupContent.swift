import SwiftUI

struct ArtworkPopupData: Codable, Equatable {
    var title: String?
    var artist: String?
    var album: String?
    var year: String?
    var releaseDate: String?
    var artworkURL: URL?
}

struct ArtworkPopupContent: View {
    var metadata: ArtworkPopupData
    var isPlaying: Bool
    var onPlayPause: () -> Void
    var onClose: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var popupForeground: Color {
        colorScheme == .light ? .white : .black
    }

    var body: some View {
        VStack(spacing: 0) {
            artwork
            HStack(spacing: 6) {
                Button {
                    onPlayPause()
                } label: {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .frame(width: 26)
                }
                .buttonStyle(.borderedProminent)

                Spacer()

                VStack(spacing: 0) {
                    Text(metadata.title ?? "No title metadata")
                        .font(.headline)
                        .lineLimit(2)
                    HStack(spacing: 6) {
                        Text(metadata.artist ?? "Unknown artist")
                            .font(.subheadline)
                            .lineLimit(1)
                        if let album = metadata.album, !album.isEmpty {
                            Text("• \(album)")
                                .font(.subheadline)
                                .lineLimit(1)
                        }
                    }
                    if let release = metadata.releaseDate {
                        Text("Release: \(release)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if let year = metadata.year {
                        Text("Year: \(year)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 8)

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
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .foregroundStyle(popupForeground)
        .frame(minWidth: 320, minHeight: 380)
    }

    private var artwork: some View {
        Group {
            if let url = metadata.artworkURL {
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
