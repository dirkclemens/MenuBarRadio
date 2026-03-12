import AppKit
import SwiftUI

/// Display and playback settings tab.
struct SettingsDisplayTabView: View {
    @EnvironmentObject private var player: RadioPlayer
    @StateObject private var deviceManager = AudioDeviceManager()

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
                    .onChange(of: player.showDockIcon) { _, newValue in
                        NSApp.setActivationPolicy(newValue ? .regular : .accessory)
                    }
                HStack {
                    Text("Volume")
                    Slider(value: Binding(
                        get: { Double(player.volume) },
                        set: { player.volume = Float($0) }
                    ), in: 0...1)
                }
                Text("Automatic output follows the system default device.")
                    .foregroundStyle(.secondary)
            }
            Section("Audio Output") {
                HStack(){
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
                    Spacer()
                    Button() {  // "Refresh Devices"
                        deviceManager.refresh()
                    } label: {
                        Image(systemName: "arrow.clockwise.circle")
                    }
                }
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
        .onAppear {
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
