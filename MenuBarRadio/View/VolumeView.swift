import SwiftUI

/// Volume slider and output device row for the current player.
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
                Text("\(Int((player.volume * 100).rounded()))%")
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 36, alignment: .trailing)
                Image(systemName: "speaker.wave.3.fill")
                    .foregroundStyle(.secondary)
            }

            OutputDevicePicker(devices: player.audioDevices)
        }
    }
}
