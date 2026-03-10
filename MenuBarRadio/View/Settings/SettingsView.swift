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
                onExport: exportStations
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
        .frame(minWidth: 720, minHeight: 480)
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
            tags: directoryStation.tags.isEmpty ? nil : directoryStation.tags
        )
        player.appendStation(station)
        selectedStationID = station.id
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
