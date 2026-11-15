import Foundation
import OSLog

/// Simple JSON persistence wrapper around UserDefaults for app settings.
final class SettingsStore {
    private let key = "MenuBarRadio.AppSettings"
    private let log = Logger(subsystem: "de.adcore.MenuBarRadio", category: "settings")

    func load() -> AppSettings {
        guard let data = UserDefaults.standard.data(forKey: key) else {
            return AppSettings.defaults
        }
        do {
            return try JSONDecoder().decode(AppSettings.self, from: data)
        } catch {
            // Keep the unreadable payload so the next save doesn't destroy it for good.
            UserDefaults.standard.set(data, forKey: key + ".unreadableBackup")
            log.error("Could not decode settings, using defaults: \(error.localizedDescription, privacy: .public)")
            return AppSettings.defaults
        }
    }

    func save(_ settings: AppSettings) {
        do {
            let data = try JSONEncoder().encode(settings)
            UserDefaults.standard.set(data, forKey: key)
        } catch {
            log.error("Could not encode settings: \(error.localizedDescription, privacy: .public)")
        }
    }
}
