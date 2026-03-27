import SwiftUI
import UniformTypeIdentifiers

/// Settings window with stations, directory search, and display options.
struct SettingsView: View {
    @EnvironmentObject private var player: RadioPlayer
    @StateObject private var directory: RadioDirectoryController
    @State private var selectedStationID: UUID?
    @State private var importErrorMessage: String?
    @State private var isShowingImporter = false
    @State private var wasPlayingBeforePreview = false

    init() {
        _directory = StateObject(wrappedValue: RadioDirectoryController(provider: RadioBrowserDirectoryProvider()))
    }

    var body: some View {
        TabView {
            SettingsStationsTabView(
                selectedStationID: $selectedStationID,
                onImport: { isShowingImporter = true },
                onExport: exportStations,
                onRefreshStation: refreshStationDetails
            )
                .tabItem {
                    Label("Stations", systemImage: "dot.radiowaves.left.and.right")
                }
            SettingsDirectoryTabView(
                directory: directory,
                wasPlayingBeforePreview: $wasPlayingBeforePreview,
                onAddStation: addDirectoryStation,
                isStationAlreadyAdded: isStationAlreadyAdded,
                detailLine: detailLine
            )
                .tabItem {
                    Label("Directory", systemImage: "magnifyingglass")
                }
            SettingsDisplayTabView()
                .tabItem {
                    Label("Display", systemImage: "text.bubble")
                }
        }
        .padding(16)
        .frame(minWidth: 620, minHeight: 520)
        .onAppear {
            selectedStationID = player.currentStation?.id ?? player.stations.first?.id
            directory.previewVolume = player.volume
            if directory.results.isEmpty {
                Task { await directory.search() }
            }
        }
        .onChange(of: player.volume) { _, newValue in
            directory.previewVolume = newValue
        }
        .alert("Import Failed", isPresented: Binding(
            get: { importErrorMessage != nil },
            set: { if !$0 { importErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importErrorMessage ?? "Unknown error.")
        }
        .fileImporter(
            isPresented: $isShowingImporter,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false,
            onCompletion: handleImportResult
        )
    }

    private var selectedStationBinding: Binding<RadioStation>? {
        guard let id = selectedStationID else { return nil }
        guard let index = player.stations.firstIndex(where: { $0.id == id }) else { return nil }
        return Binding(
            get: { player.stations[index] },
            set: { player.stations[index] = $0 }
        )
    }

    /// Imports stations from a JSON file.
    private func handleImportResult(_ result: Result<[URL], Error>) {
        do {
            let urls = try result.get()
            guard let url = urls.first else { return }
            let didStartAccess = url.startAccessingSecurityScopedResource()
            defer {
                if didStartAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            guard didStartAccess else {
                throw NSError(
                    domain: "MenuBarRadio.Import",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Missing security-scoped access for the selected file."]
                )
            }
            let data = try Data(contentsOf: url)

            let importedStations: [RadioStation]
            if let payload = try? JSONDecoder().decode(ImportPayload.self, from: data) {
                importedStations = payload.stations
            } else {
                importedStations = try JSONDecoder().decode([RadioStation].self, from: data)
            }

            player.replaceStations(with: importedStations)
            selectedStationID = player.currentStation?.id ?? player.stations.first?.id
        } catch {
            importErrorMessage = "Could not import stations: \(error.localizedDescription)"
        }
    }

    /// Exports all stations to a JSON file chosen by the user.
    private func exportStations() {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.json]
        savePanel.canCreateDirectories = true
        savePanel.isExtensionHidden = false
        savePanel.nameFieldStringValue = "MenuBarRadioStations.json"

        guard savePanel.runModal() == .OK, let url = savePanel.url else { return }

        do {
            let payload = ExportPayload(version: 1, exportedAt: Date(), stations: player.stations)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(payload)
            try data.write(to: url, options: [.atomic])
        } catch {
            importErrorMessage = "Could not export stations: \(error.localizedDescription)"
        }
    }

    /// Formats a compact description for directory results.
    private func detailLine(for station: RadioDirectoryStation) -> String {
        let countryPart = station.country.isEmpty ? station.countryCode : station.country
        let codecPart = station.codec.isEmpty ? "n/a" : station.codec.uppercased()
        let bitratePart = station.bitrate.map { "\($0) kbps" } ?? "?"
        let votesPart = station.votes.map { "votes: \($0)" } ?? "votes: ?"
        let tagsPart = station.tags.isEmpty ? "" : " • \(station.tags)"
        return "\(countryPart) • \(station.language) • \(codecPart) • \(bitratePart) • \(votesPart) \(tagsPart)"
    }

    /// Prevents duplicates by matching stream URLs.
    private func isStationAlreadyAdded(_ directoryStation: RadioDirectoryStation) -> Bool {
        guard let url = directoryStation.preferredStreamURL?.absoluteString else { return false }
        return player.stations.contains { $0.streamURL.caseInsensitiveCompare(url) == .orderedSame }
    }

    /// Adds a directory result into the user's station list.
    private func addDirectoryStation(_ directoryStation: RadioDirectoryStation) {
        guard let url = directoryStation.preferredStreamURL?.absoluteString else { return }
        guard !isStationAlreadyAdded(directoryStation) else { return }

        let station = RadioStation(
            name: directoryStation.name,
            streamURL: url,
            metadataURL: nil,
            isFavorite: false,
            codec: directoryStation.codec.isEmpty ? nil : directoryStation.codec,
            bitrate: directoryStation.bitrate,
            votes: directoryStation.votes,
            tags: directoryStation.tags.isEmpty ? nil : directoryStation.tags,
            country: directoryStation.country.isEmpty ? nil : directoryStation.country,
            countryCode: directoryStation.countryCode.isEmpty ? nil : directoryStation.countryCode,
            state: directoryStation.state.isEmpty ? nil : directoryStation.state,
            language: directoryStation.language.isEmpty ? nil : directoryStation.language,
            languageCodes: directoryStation.languageCodes.isEmpty ? nil : directoryStation.languageCodes,
            homepageURL: directoryStation.homepageURL,
            faviconURL: directoryStation.faviconURL,
            geoLatitude: directoryStation.geoLatitude,
            geoLongitude: directoryStation.geoLongitude,
            geoDistance: directoryStation.geoDistance
        )
        NSLog(
            "Directory station details: country=%@ countryCode=%@ state=%@ language=%@ languageCodes=%@ homepage=%@ favicon=%@ geo_lat=%@ geo_long=%@ geo_distance=%@",
            station.country ?? "nil",
            station.countryCode ?? "nil",
            station.state ?? "nil",
            station.language ?? "nil",
            station.languageCodes ?? "nil",
            station.homepageURL?.absoluteString ?? "nil",
            station.faviconURL?.absoluteString ?? "nil",
            station.geoLatitude.map { String($0) } ?? "nil",
            station.geoLongitude.map { String($0) } ?? "nil",
            station.geoDistance.map { String($0) } ?? "nil"
        )
        player.appendStation(station)
        selectedStationID = station.id
    }

    private func refreshStationDetails(_ station: RadioStation) async {
        let provider = RadioBrowserDirectoryProvider()
        let query = RadioDirectorySearchQuery(
            text: station.name,
            countryCode: station.countryCode ?? "",
            tag: "",
            limit: 60,
            hideBroken: true
        )

        do {
            let results = try await provider.searchStations(query: query)
            guard let match = bestDirectoryMatch(for: station, in: results) else { return }
            let updated = mergeStation(station, with: match)
            await MainActor.run {
                player.updateStation(updated)
            }
        } catch {
            NSLog("Refresh details failed for \(station.name): \(error.localizedDescription)")
        }
    }

    private func bestDirectoryMatch(for station: RadioStation, in results: [RadioDirectoryStation]) -> RadioDirectoryStation? {
        guard !results.isEmpty else { return nil }
        let target = station.streamURL.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let urlMatches = results.filter { result in
            let candidates = [result.preferredStreamURL, result.streamURL]
                .compactMap { $0?.absoluteString.lowercased() }
            return candidates.contains(target)
        }
        if let bestURLMatch = urlMatches.max(by: { ($0.votes ?? 0) < ($1.votes ?? 0) }) {
            return bestURLMatch
        }
        let nameMatches = results.filter { $0.name.caseInsensitiveCompare(station.name) == .orderedSame }
        if let bestNameMatch = nameMatches.max(by: { ($0.votes ?? 0) < ($1.votes ?? 0) }) {
            return bestNameMatch
        }
        return results.max(by: { ($0.votes ?? 0) < ($1.votes ?? 0) }) ?? results.first
    }

    private func mergeStation(_ station: RadioStation, with directory: RadioDirectoryStation) -> RadioStation {
        var updated = station
        updated.codec = directory.codec.isEmpty ? station.codec : directory.codec
        updated.bitrate = directory.bitrate ?? station.bitrate
        updated.votes = directory.votes ?? station.votes
        updated.tags = directory.tags.isEmpty ? station.tags : directory.tags
        updated.country = directory.country.isEmpty ? station.country : directory.country
        updated.countryCode = directory.countryCode.isEmpty ? station.countryCode : directory.countryCode
        updated.state = directory.state.isEmpty ? station.state : directory.state
        updated.language = directory.language.isEmpty ? station.language : directory.language
        updated.languageCodes = directory.languageCodes.isEmpty ? station.languageCodes : directory.languageCodes
        updated.homepageURL = directory.homepageURL ?? station.homepageURL
        updated.faviconURL = directory.faviconURL ?? station.faviconURL
        updated.geoLatitude = directory.geoLatitude ?? station.geoLatitude
        updated.geoLongitude = directory.geoLongitude ?? station.geoLongitude
        updated.geoDistance = directory.geoDistance ?? station.geoDistance
        return updated
    }
}

/// JSON import payload wrapper.
private struct ImportPayload: Codable {
    let stations: [RadioStation]
}

/// JSON export payload wrapper.
private struct ExportPayload: Codable {
    let version: Int
    let exportedAt: Date
    let stations: [RadioStation]
}
