//
//  MenuBarRadioApp.swift
//  MenuBarRadio
//

import SwiftUI

// App entry point: installs the menu bar extra and settings window.
@main
struct MenuBarRadioApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
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

// necessary to hide the Dock icon and keep the app running in the menu bar
class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // no Dock Icon
        NSApp.setActivationPolicy(.accessory)
    }
}
