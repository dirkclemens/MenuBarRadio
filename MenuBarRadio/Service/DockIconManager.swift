import AppKit

enum DockIconManager {
    static func apply(showDockIcon: Bool) {
        let policy: NSApplication.ActivationPolicy = showDockIcon ? .regular : .accessory
        // NSApp may not exist yet when called from App.init; defer to the next run loop turn.
        DispatchQueue.main.async {
            guard NSApp.activationPolicy() != policy else { return }
            NSApp.setActivationPolicy(policy)
        }
    }
}
