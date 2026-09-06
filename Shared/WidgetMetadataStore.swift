import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif
import OSLog

struct WidgetMetadataSnapshot: Codable, Equatable {
    let artworkData: ArtworkPopupData
    let isPlaying: Bool
    let reportedAt: Date
}

final class WidgetMetadataStore {
    static let shared = WidgetMetadataStore()

    private let appGroupID = "group.de.adcore.MenuBarRadio"
    private let defaults: UserDefaults?
    private let key = "MenuBarRadio.WidgetMetadata"
    private let widgetKind = "MenuBarRadioWidget"
    private let log = Logger(subsystem: "de.adcore.MenuBarRadio.WidgetMetadataStore", category: "shared")

    private init() {
        defaults = UserDefaults(suiteName: appGroupID)
        if defaults == nil {
            log.error("App Group UserDefaults unavailable for \(self.appGroupID)")
        }
        if FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) == nil {
            log.error("App Group container unavailable for \(self.appGroupID)")
        } else {
            log.debug("App Group container is available for \(self.appGroupID)")
        }
    }

    func save(metadata: ArtworkPopupData, isPlaying: Bool) {
        guard let defaults else {
            log.error("Cannot save snapshot because shared defaults are unavailable")
            return
        }

        let snapshot = WidgetMetadataSnapshot(
            artworkData: metadata,
            isPlaying: isPlaying,
            reportedAt: Date()
        )

        guard let data = try? JSONEncoder().encode(snapshot) else {
            log.error("Failed to encode widget snapshot")
            return
        }
        defaults.set(data, forKey: key)
        log.debug("Saved snapshot (playing: \(snapshot.isPlaying))")
        log.debug("\(metadata.title as NSObject?) - \(metadata.artist as NSObject?) - \(metadata.artworkURL as NSObject?)")

        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadTimelines(ofKind: widgetKind)
        #endif
    }

    func loadSnapshot() -> WidgetMetadataSnapshot? {
        guard let defaults else {
            log.error("Cannot load snapshot because shared defaults are unavailable")
            return nil
        }
        guard let data = defaults.data(forKey: key) else {
            log.debug("No snapshot data available")
            return nil
        }
        do {
            let snapshot = try JSONDecoder().decode(WidgetMetadataSnapshot.self, from: data)
            log.debug("Loaded snapshot (playing: \(snapshot.isPlaying))")
            return snapshot
        } catch {
            log.error("Failed to decode widget snapshot: \(error.localizedDescription)")
            return nil
        }
    }
}
