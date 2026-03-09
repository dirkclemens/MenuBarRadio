import SwiftUI

struct ArtworkView: View {
    let metadata: NowPlayingMetadata

    var body: some View {
        Group {
            if let artworkURL = metadata.artworkURL {
                AsyncImage(url: artworkURL) { phase in
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
        .frame(width: 128, height: 128)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var placeholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(.quaternary)
            Image(systemName: "music.note")
                .foregroundStyle(.secondary)
        }
    }
}
