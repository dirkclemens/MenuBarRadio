import Foundation

/// Static app information shared by all network clients.
nonisolated enum AppInfo {
    static let name = "MenuBarRadio"

    static let version: String =
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0"

    /// `MenuBarRadio/<version>`, used for every HTTP request (streams and APIs).
    static let userAgent = "\(name)/\(version)"
}
