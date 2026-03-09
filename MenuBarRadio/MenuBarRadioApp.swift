//
//  MenuBarRadioApp.swift
//  MenuBarRadio
//

import SwiftUI

@main
struct MenuBarRadioApp: App {
    @StateObject private var player = RadioPlayer()

    var body: some Scene {
        MenuBarExtra {
            ContentView()
                .environmentObject(player)
        } label: {
            MenuBarLabelView()
                .environmentObject(player)
                .help(player.menuBarTooltip)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(player)
        }
    }
}
