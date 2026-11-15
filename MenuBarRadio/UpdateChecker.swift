//
//  UpdateChecker.swift
//  MenuBarRadio
//

import Foundation
import OSLog

/// Fire-and-forget "is a newer version available" check against
/// https://api.adcore.de/apps/check.php. Purely informational for now —
/// the result is only logged, nothing else happens with it yet.
enum UpdateChecker {
    private static let endpoint = URL(string: "https://api.adcore.de/apps/check.php")!
    nonisolated private static let log = Logger(subsystem: "de.adcore.MenuBarRadio", category: "update")

    static func checkForUpdate() {
        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "app", value: AppInfo.name),
            URLQueryItem(name: "version", value: AppInfo.version),
            URLQueryItem(name: "os", value: ProcessInfo.processInfo.operatingSystemVersionString),
            URLQueryItem(name: "arch", value: currentArchitecture),
        ]
        guard let url = components.url else { return }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue(AppInfo.userAgent, forHTTPHeaderField: "User-Agent")

        Task.detached(priority: .utility) {
            guard let (data, _) = try? await URLSession.shared.data(for: request),
                  let result = try? JSONDecoder().decode(UpdateCheckResponse.self, from: data)
            else { return }
            log.info("current=\(result.currentVersion ?? "?", privacy: .public) latest=\(result.latestVersion ?? "?", privacy: .public) updateAvailable=\(result.updateAvailable ?? false)")
        }
    }

    private static var currentArchitecture: String {
        #if arch(arm64)
        return "arm64"
        #elseif arch(x86_64)
        return "x86_64"
        #else
        return "unknown"
        #endif
    }
}

nonisolated private struct UpdateCheckResponse: Decodable {
    let app: String?
    let currentVersion: String?
    let latestVersion: String?
    let updateAvailable: Bool?
    let downloadURL: String?

    enum CodingKeys: String, CodingKey {
        case app
        case currentVersion = "current_version"
        case latestVersion = "latest_version"
        case updateAvailable = "update_available"
        case downloadURL = "download_url"
    }
}
