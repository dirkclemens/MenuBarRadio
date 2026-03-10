import Foundation

/// Simple JSON persistence wrapper around UserDefaults for app settings.
final class SettingsStore {
    private let key = "MenuBarRadio.AppSettings"

    func load() -> AppSettings {
        guard
            let data = UserDefaults.standard.data(forKey: key),
            let settings = try? JSONDecoder().decode(AppSettings.self, from: data)
        else {
            return AppSettings.defaults
        }

        return settings
    }

    func save(_ settings: AppSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
