import SwiftUI

struct MenuBarLabelView: View {
    @EnvironmentObject private var player: RadioPlayer

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: player.isPlaying ? "dot.radiowaves.left.and.right" : "radio")
            Text(player.menuBarLabel)
                .lineLimit(1)
        }
    }
}
