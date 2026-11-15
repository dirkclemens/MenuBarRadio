import AppKit
import SwiftUI

/// Display and playback settings tab.
struct SettingsDisplayTabView: View {
    @EnvironmentObject private var player: RadioPlayer
    @StateObject private var loginItemManager = LoginItemManager()

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
                Toggle("Restore artwork popup on app launch", isOn: $player.restoreArtworkPopupOnLaunch)
                Toggle("Show Dock icon", isOn: $player.showDockIcon)
                Toggle("Launch at login", isOn: Binding(
                    get: { loginItemManager.isEnabled },
                    set: { loginItemManager.setEnabled($0) }
                ))
                if let error = loginItemManager.lastError {
                    Text(error)
                        .foregroundStyle(.red)
                }
            }
            Section("Audio Output") {
                OutputDevicePicker(devices: player.audioDevices)
                Text("Only MenuBar Radio is routed to the selected device; the system output stays unchanged. If the device is disconnected, playback falls back to the system default and switches back when it returns.")
                    .foregroundStyle(.secondary)
            }
            Section("Metadata Polling") {
                Stepper(value: $player.metadataRefreshSeconds, in: 5...60, step: 1) {
                    Text("Provider metadata refresh interval: \(Int(player.metadataRefreshSeconds)) seconds")
                }
                Text("Used only when a station has a metadata API URL configured.")
                    .foregroundStyle(.secondary)
            }
            Section("History") {
                Stepper(value: $player.songHistoryLimit, in: 0...50, step: 1) {
                    Text("Keep last \(player.songHistoryLimit) tracks")
                }
                Text("Set to 0 to disable the recent tracks list.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            loginItemManager.refresh()
        }
    }
}
