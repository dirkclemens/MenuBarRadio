//
//  MenuBarRadioApp.swift
//  MenuBarRadio
//

import AppKit
import SwiftUI

// App entry point: installs the menu bar extra and settings window.
@main
struct MenuBarRadioApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var player: RadioPlayer

    init() {
        let player = RadioPlayer()
        _player = StateObject(wrappedValue: player)
        if player.restoreArtworkPopupOnLaunch,
           ArtworkPopupWindowController.shared.wasOpenLastSession {
            DispatchQueue.main.async {
                ArtworkPopupWindowController.shared.show(with: player)
            }
        }
        
        let showDockIcon = UserDefaults.standard.bool(forKey: "showDockIcon")
        DockIconManager.apply(showDockIcon: showDockIcon)
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

// necessary to hide the Dock icon and keep the app running in the menu bar
class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // handled by Settings via RadioPlayer.showDockIcon
//        NSApp.setActivationPolicy(.accessory)
    }
}
