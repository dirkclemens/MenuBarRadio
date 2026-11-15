//
//  MenuBarRadioApp.swift
//  MenuBarRadio
//

import AppKit
import SwiftUI

// App entry point: installs the menu bar extra and settings window.
@main
struct MenuBarRadioApp: App {
    @StateObject private var player: RadioPlayer

    init() {
        let player = RadioPlayer()
        _player = StateObject(wrappedValue: player)

        DockIconManager.apply(showDockIcon: player.showDockIcon)

        if player.restoreArtworkPopupOnLaunch,
           ArtworkPopupWindowController.shared.wasOpenLastSession {
            DispatchQueue.main.async {
                ArtworkPopupWindowController.shared.show(with: player)
            }
        }

        UpdateChecker.checkForUpdate()
    }

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
