import SwiftUI

/// Output device picker shared by the menu popover and the settings window.
/// Routing applies to this app only; the system default output is never changed.
struct OutputDevicePicker: View {
    @EnvironmentObject private var player: RadioPlayer
    @ObservedObject var devices: AudioDeviceManager

    var body: some View {
        HStack {
            Picker("Output Device", selection: $player.selectedOutputDeviceUID) {
                Text("Automatic (System Default)")
                    .tag(String?.none)
                if let uid = player.selectedOutputDeviceUID, !devices.contains(uid: uid) {
                    // Remembered device that is currently disconnected; playback uses the default.
                    Text("Unavailable Device (using default)")
                        .tag(String?.some(uid))
                }
                ForEach(devices.devices) { device in
                    Text(device.name)
                        .tag(String?.some(device.uid))
                }
            }
            Button {
                devices.refresh()
            } label: {
                Image(systemName: "arrow.clockwise.circle")
            }
            .buttonStyle(.borderless)
            .help("Refresh Devices")
        }
    }
}
