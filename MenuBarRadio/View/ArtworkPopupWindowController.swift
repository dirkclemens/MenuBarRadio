import AppKit
import SwiftUI

/// Manages a floating artwork popup window.
final class ArtworkPopupWindowController {
    static let shared = ArtworkPopupWindowController()

    private var window: NSWindow?
    private var hostingView: NSHostingView<AnyView>?
    private let frameDefaultsKey = "MenuBarRadio.ArtworkPopupWindowFrame"
    private let wasOpenDefaultsKey = "MenuBarRadio.ArtworkPopupWindowWasOpen"

    private init() {}

    var wasOpenLastSession: Bool {
        UserDefaults.standard.bool(forKey: wasOpenDefaultsKey)
    }

    /// Shows the popup. `activate: false` is used for automatic restores so the
    /// window appears without taking keyboard focus away from the frontmost app.
    func show(with player: RadioPlayer, activate: Bool = true) {
        if let window {
            present(window, activate: activate)
            return
        }

        let contentView = ArtworkPopupView { [weak self] in
            self?.close()
        }
        .environmentObject(player)

        let hostingView = NSHostingView(rootView: AnyView(contentView))
        self.hostingView = hostingView

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 480),
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
        restoreWindowFrameIfAvailable(window)
        window.contentView = hostingView

        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.invalidateShadow()

        window.collectionBehavior.insert(.moveToActiveSpace)
        window.setFrameAutosaveName("MenuBarRadioArtworkPopupWindow")
        window.minSize = NSSize(width: 320, height: 380)

        if let contentView = window.contentView {
            contentView.wantsLayer = true
            contentView.layer?.cornerRadius = 16
            contentView.layer?.masksToBounds = true
        }

        self.window = window
        present(window, activate: activate)
        UserDefaults.standard.set(true, forKey: wasOpenDefaultsKey)
    }

    private func present(_ window: NSWindow, activate: Bool) {
        if activate {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate()
        } else {
            window.orderFrontRegardless()
        }
    }

    func close() {
        if let window {
            saveWindowFrame(window)
        }
        UserDefaults.standard.set(false, forKey: wasOpenDefaultsKey)
        window?.orderOut(nil)
        window = nil
        hostingView = nil
    }

    private func positionWindowTopLeft(_ window: NSWindow) {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let padding: CGFloat = 12
        let topLeft = NSPoint(x: visible.minX + padding, y: visible.maxY - padding)
        window.setFrameTopLeftPoint(topLeft)
    }

    private func restoreWindowFrameIfAvailable(_ window: NSWindow) {
        if let saved = UserDefaults.standard.string(forKey: frameDefaultsKey) {
            let frame = NSRectFromString(saved)
            if frame.width > 0, frame.height > 0 {
                window.setFrame(frame, display: false)
                return
            }
        }
        positionWindowTopLeft(window)
    }

    private func saveWindowFrame(_ window: NSWindow) {
        let frame = NSStringFromRect(window.frame)
        UserDefaults.standard.set(frame, forKey: frameDefaultsKey)
    }
}
