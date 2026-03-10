import SwiftUI

struct VolumeView: View {
    @EnvironmentObject private var player: RadioPlayer

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Volume")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Image(systemName: "speaker.fill")
                    .foregroundStyle(.secondary)
                Slider(value: Binding(
                    get: { Double(player.volume) },
                    set: { player.volume = Float($0) }
                ), in: 0...1)
                Image(systemName: "speaker.wave.3.fill")
                    .foregroundStyle(.secondary)
            }
        }
    }
}
