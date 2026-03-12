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
        window.makeKeyAndOrderFront(nil)        
//        window.backgroundColor = .clear
        window.backgroundColor = NSColor.gray.withAlphaComponent(0.25)
        window.isOpaque = false
        window.invalidateShadow()
        window.contentView?.wantsLayer = true
        window.contentView?.layer?.cornerRadius = 16.0
        window.contentView?.layer?.masksToBounds = true
//        window.collectionBehavior.insert(.canJoinAllSpaces)
        window.collectionBehavior.insert(.moveToActiveSpace)
        window.setFrameAutosaveName("MenuBarRadioArtworkPopupWindow")

//        window.contentView?.layer?.state = .active
//        window.contentView?.layer?.material = .light

        NSApp.activate(ignoringOtherApps: true)
        self.window = window
        UserDefaults.standard.set(true, forKey: wasOpenDefaultsKey)
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
