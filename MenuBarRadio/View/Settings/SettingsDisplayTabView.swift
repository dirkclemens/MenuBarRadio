import SwiftUI

/// Display and playback settings tab.
struct SettingsDisplayTabView: View {
    @EnvironmentObject private var player: RadioPlayer

    var body: some View {
        Form {
            Section("Menu Bar Label") {
                Toggle("Show Artist", isOn: $player.menuBarDisplay.showArtist)
                Toggle("Show Song Title", isOn: $player.menuBarDisplay.showTitle)
                Toggle("Show Release Date (Year)", isOn: $player.menuBarDisplay.showYear)
                Toggle("Fallback to Station Name if metadata is missing", isOn: $player.menuBarDisplay.showStationNameFallback)
                Stepper(value: $player.menuBarDisplay.maxLength, in: 12...80) {
                    Text("Maximum Label Length: \(player.menuBarDisplay.maxLength)")
                }
            }
            Section("Playback") {
                Toggle("Auto-play last station on app launch", isOn: $player.autoPlayOnLaunch)
                HStack {
                    Text("Volume")
                    Slider(value: Binding(
                        get: { Double(player.volume) },
                        set: { player.volume = Float($0) }
                    ), in: 0...1)
                }
                Text("Audio output follows the default macOS output device.")
                    .foregroundStyle(.secondary)
            }
            Section("Metadata Polling") {
                Stepper(value: $player.metadataRefreshSeconds, in: 5...60, step: 1) {
                    Text("Provider metadata refresh interval: \(Int(player.metadataRefreshSeconds)) seconds")
                }
                Text("Used only when a station has a metadata API URL configured.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
