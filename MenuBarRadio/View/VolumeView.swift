import SwiftUI

/// Volume slider row for the current player.
struct VolumeView: View {
    @EnvironmentObject private var player: RadioPlayer
    @StateObject private var deviceManager = AudioDeviceManager()

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
            
            HStack {
                Picker("Output Device", selection: $player.selectedOutputDeviceID) {
                    Text("Automatic (System Default)")
                        .tag(UInt32(0))
                    if player.selectedOutputDeviceID != 0,
                       !deviceManager.isValidOutputDevice(id: player.selectedOutputDeviceID) {
                        Text("Unavailable Device")
                            .tag(player.selectedOutputDeviceID)
                            .hidden()
                    }
                    ForEach(deviceManager.devices) { device in
                        Text(device.name)
                            .tag(UInt32(device.id))
                    }
                }
                .onChange(of: player.selectedOutputDeviceID) { _, newValue in
                    if newValue != 0 {
                        _ = deviceManager.setDefaultOutputDevice(id: newValue)
                        deviceManager.setDeviceVolume(id: newValue, volume: player.volume)
                    }
                }
                Button() {  // "Refresh Devices"
                    deviceManager.refresh()
                } label: {
                    Image(systemName: "arrow.clockwise.circle")
                }
            }
        }
        .task {
            deviceManager.refresh()
            if player.selectedOutputDeviceID != 0,
               !deviceManager.isValidOutputDevice(id: player.selectedOutputDeviceID) {
                player.selectedOutputDeviceID = 0
            }
        }
        .onChange(of: deviceManager.devices) { _, _ in
            if player.selectedOutputDeviceID != 0,
               !deviceManager.isValidOutputDevice(id: player.selectedOutputDeviceID) {
                player.selectedOutputDeviceID = 0
            }
        }
    }
}
