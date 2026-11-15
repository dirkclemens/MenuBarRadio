//
//  MenuBarRadioApp.swift
//  MenuBarRadio
//

import AppKit
import SwiftUI

/// Process entry point. When the app only hosts unit tests, a blank app is started
/// instead so tests never start playback, touch settings or make network requests.
@main
enum AppEntry {
    static let isRunningTests: Bool = {
        let environment = ProcessInfo.processInfo.environment
        return environment["XCTestConfigurationFilePath"] != nil
            || environment["XCTestBundlePath"] != nil
            || environment["XCTestSessionIdentifier"] != nil
    }()

    static func main() {
        if isRunningTests {
            TestHostApp.main()
        } else {
            MenuBarRadioApp.main()
        }
    }
}

/// Minimal app used as test host.
private struct TestHostApp: App {
    var body: some Scene {
        Settings { EmptyView() }
    }
}

/// Installs the menu bar extra and settings window.
struct MenuBarRadioApp: App {
    @StateObject private var player: RadioPlayer

    init() {
        let player = RadioPlayer()
        _player = StateObject(wrappedValue: player)

        DockIconManager.apply(showDockIcon: player.showDockIcon)

        if player.restoreArtworkPopupOnLaunch,
           ArtworkPopupWindowController.shared.wasOpenLastSession {
            DispatchQueue.main.async {
                ArtworkPopupWindowController.shared.show(with: player, activate: false)
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
