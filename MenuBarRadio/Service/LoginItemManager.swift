import ServiceManagement
import SwiftUI
import Combine

@MainActor
final class LoginItemManager: ObservableObject {
    @Published private(set) var isEnabled: Bool = false
    @Published var lastError: String?

    init() {
        refresh()
    }

    func refresh() {
        isEnabled = (SMAppService.mainApp.status == .enabled)
    }

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            refresh()
            lastError = nil
        } catch {
            refresh()
            lastError = error.localizedDescription
        }
    }
}
