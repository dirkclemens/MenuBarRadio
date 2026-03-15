import SwiftUI

/// Station picker and play/pause control row.
struct HeaderView: View {
    @EnvironmentObject private var player: RadioPlayer

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "radio")
                .font(.system(size: 16, weight: .semibold))

            Picker("Station", selection: Binding<UUID?>(
                get: { player.currentStation?.id },
                set: { newValue in
                    guard let id = newValue else { return }
                    player.selectStation(id: id)
                }
            )) {
                ForEach(player.stations) { station in
                    Text(station.name).tag(Optional(station.id))
                }
            }
            .labelsHidden()
            .frame(maxWidth: .infinity)

            Button {
                player.togglePlayPause()
            } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .frame(width: 22)
            }
            .buttonStyle(.borderedProminent)
        }
    }
}
