import AppKit
import SwiftUI

/// Manages a floating artwork popup window.
final class ArtworkPopupWindowController {
    static let shared = ArtworkPopupWindowController()

    private var window: NSWindow?
    private var hostingView: NSHostingView<AnyView>?

    private init() {}

    func show(with player: RadioPlayer) {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let contentView = ArtworkPopupView { [weak self] in
            self?.close()
        }
        .environmentObject(player)

        let hostingView = NSHostingView(rootView: AnyView(contentView))
        self.hostingView = hostingView

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 380),
            styleMask: [.hudWindow, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.title = "" //  "Now Playing"
        window.center()
        window.contentView = hostingView
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
    }

    func close() {
        window?.orderOut(nil)
        window = nil
        hostingView = nil
    }
}
