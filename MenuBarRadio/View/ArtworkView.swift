import SwiftUI

/// Artwork renderer with placeholder and clipboard copy action.
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
        .frame(width: 160, height: 160)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .contextMenu {
            Button("Copy Artwork") {
                Task {
                    await copyArtworkToClipboard()
                }
            }
            .disabled(metadata.artworkURL == nil)
        }
    }

    private var placeholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(.quaternary)
            Image(systemName: "music.note")
                .foregroundStyle(.secondary)
        }
    }

    /// Copies the current artwork into the system clipboard.
    private func copyArtworkToClipboard() async {
        guard let artworkURL = metadata.artworkURL else { return }

        let image = await loadImage(from: artworkURL)

        guard let image else { return }
        await MainActor.run {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.writeObjects([image])
        }
    }

    /// Loads artwork via URLSession to avoid blocking the main thread.
    private func loadImage(from url: URL) async -> NSImage? {
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            return NSImage(data: data)
        } catch {
            return nil
        }
    }
}
