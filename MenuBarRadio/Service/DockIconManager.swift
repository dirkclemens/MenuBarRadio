import AppKit

enum DockIconManager {
    static func apply(showDockIcon: Bool) {
        DispatchQueue.main.async {
            NSApp.setActivationPolicy(showDockIcon ? .regular : .accessory)
        }
    }
}
