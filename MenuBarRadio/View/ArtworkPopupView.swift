import SwiftUI

/// Floating artwork window content with basic playback controls.
struct ArtworkPopupView: View {
    @EnvironmentObject private var player: RadioPlayer

    let onClose: () -> Void

    var body: some View {
        ArtworkPopupContent(
            metadata: .init(nowPlaying: player.nowPlaying),
            isPlaying: player.isPlaying,
            onPlayPause: player.togglePlayPause,
            onClose: onClose
        )
    }
}

private extension ArtworkPopupData {
    init(nowPlaying: NowPlayingMetadata) {
        self.init(
            title: nowPlaying.title,
            artist: nowPlaying.artist,
            album: nowPlaying.album,
            year: nowPlaying.releaseYear,
            releaseDate: nowPlaying.formattedReleaseDate(),
            artworkURL: nowPlaying.artworkURL
        )
    }
}
