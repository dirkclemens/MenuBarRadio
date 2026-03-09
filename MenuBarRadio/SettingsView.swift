import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject private var player: RadioPlayer
    @StateObject private var directory: RadioDirectoryController
    @State private var selectedStationID: UUID?
    @State private var importErrorMessage: String?
    @State private var isShowingImporter = false

    init() {
        _directory = StateObject(wrappedValue: RadioDirectoryController(provider: RadioBrowserDirectoryProvider()))
    }

    var body: some View {
        TabView {
            stationsTab
                .tabItem {
                    Label("Stations", systemImage: "dot.radiowaves.left.and.right")
                }
            directoryTab
                .tabItem {
                    Label("Directory", systemImage: "magnifyingglass")
                }
            displayTab
                .tabItem {
                    Label("Display", systemImage: "text.bubble")
                }
        }
        .padding(16)
        .frame(minWidth: 720, minHeight: 480)
        .onAppear {
            selectedStationID = player.currentStation?.id ?? player.stations.first?.id
            if directory.results.isEmpty {
                Task { await directory.search() }
            }
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

    private var stationsTab: some View {
        HStack() {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Stations")
                        .font(.headline)
                    Spacer()
                    Button("Import") {
                        isShowingImporter = true
                    }
//                    .buttonStyle(.plain)
                    Button("Export") {
                        exportStations()
                    }
//                    .buttonStyle(.plain)
                    Button {
                        if let id = selectedStationID {
                            player.deleteStation(id: id)
                            selectedStationID = player.stations.first?.id
                        }
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .frame(width: 24, height: 24)
                    .buttonStyle(.bordered)
                    .disabled(selectedStationID == nil)

                    Button {
                        player.addStation()
                        selectedStationID = player.stations.last?.id
                    } label: {
                        Image(systemName: "plus.circle")
                    }
                    .frame(width: 24, height: 24)
                    .buttonStyle(.bordered)
                }

                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(player.stations) { station in
                            Button {
                                selectedStationID = station.id
                            } label: {
                                HStack {
                                    Text(station.name)
                                        .lineLimit(1)
                                    Spacer()
                                    if station.isFavorite {
                                        Image(systemName: "star.fill")
                                            .foregroundStyle(.yellow)
                                    }
                                }
                                .padding(.vertical, 6)
                                .padding(.horizontal, 8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(selectedStationID == station.id ? Color.accentColor.opacity(0.2) : Color.clear)
                                )
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button("Delete Station", role: .destructive) {
                                    player.deleteStation(id: station.id)
                                    if selectedStationID == station.id {
                                        selectedStationID = player.stations.first?.id
                                    }
                                }
                            }
                        }
                    }
                }
//                .frame(height: 340)
            }
            .frame(width: 280)

            Divider()

            if let stationBinding = selectedStationBinding {
                StationEditor(station: stationBinding) { updated in
                    player.updateStation(updated)
                } onPlay: { station in
                    player.selectStation(id: station.id, autoPlay: true)
                }
            } else {
                ContentUnavailableView("Select a station", systemImage: "radio")
            }
        }
    }

    private var displayTab: some View {
        Form {
            Section("Menu Bar Label") {
                Toggle("Show Artist", isOn: $player.menuBarDisplay.showArtist)
                Toggle("Show Song Title", isOn: $player.menuBarDisplay.showTitle)
                Toggle("Show Year", isOn: $player.menuBarDisplay.showYear)
                Toggle("Fallback to Station Name if metadata is missing", isOn: $player.menuBarDisplay.showStationNameFallback)
                Stepper(value: $player.menuBarDisplay.maxLength, in: 12...80) {
                    Text("Maximum Label Length: \(player.menuBarDisplay.maxLength)")
                }
            }
            Section("Playback") {
                Toggle("Auto-play last station on app launch", isOn: $player.autoPlayOnLaunch)
                HStack {
                    Text("Volume")
                    Slider(value: Binding(
                        get: { Double(player.volume) },
                        set: { player.volume = Float($0) }
                    ), in: 0...1)
                }
                Text("Audio output follows the default macOS output device.")
                    .foregroundStyle(.secondary)
            }
            Section("Metadata Polling") {
                Stepper(value: $player.metadataRefreshSeconds, in: 5...60, step: 1) {
                    Text("Provider metadata refresh interval: \(Int(player.metadataRefreshSeconds)) seconds")
                }
                Text("Used only when a station has a metadata API URL configured.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var directoryTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Provider: \(directory.providerName)")
                    .font(.headline)
                Spacer()
            }

            HStack(spacing: 8) {
                TextField("Search by station name", text: $directory.queryText)
                    .textFieldStyle(.roundedBorder)
                TextField("Country code (e.g. DE, US)", text: $directory.queryCountryCode)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 180)
                TextField("Tag (optional)", text: $directory.queryTag)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 180)
                Button("Search") {
                    Task { await directory.search() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(directory.isSearching)
            }

            if directory.isSearching {
                ProgressView("Searching stations...")
            } else if let errorMessage = directory.errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
            }

            List(directory.results, id: \.id) { station in
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(station.name)
                            .font(.headline)
                            .lineLimit(1)
                        Text(detailLine(for: station))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Button(directory.previewingStationID == station.id ? "Stop" : "Pre-Listen") {
                        directory.togglePreview(for: station)
                    }
                    .disabled(station.preferredStreamURL == nil)

                    Button(isStationAlreadyAdded(station) ? "Added" : "Add") {
                        addDirectoryStation(station)
                    }
                    .disabled(isStationAlreadyAdded(station) || station.preferredStreamURL == nil)
                }
            }
        }
    }

    private var selectedStationBinding: Binding<RadioStation>? {
        guard let id = selectedStationID else { return nil }
        guard let index = player.stations.firstIndex(where: { $0.id == id }) else { return nil }
        return Binding(
            get: { player.stations[index] },
            set: { player.stations[index] = $0 }
        )
    }

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

    private func detailLine(for station: RadioDirectoryStation) -> String {
        let countryPart = station.country.isEmpty ? station.countryCode : station.country
        let codecPart = station.codec.isEmpty ? "n/a" : station.codec.uppercased()
        let bitratePart = station.bitrate.map { "\($0) kbps" } ?? "?"
        let votesPart = station.votes.map { "votes: \($0)" } ?? "votes: ?"
        return "\(countryPart) • \(station.language) • \(codecPart) • \(bitratePart) • \(votesPart)"
    }

    private func isStationAlreadyAdded(_ directoryStation: RadioDirectoryStation) -> Bool {
        guard let url = directoryStation.preferredStreamURL?.absoluteString else { return false }
        return player.stations.contains { $0.streamURL.caseInsensitiveCompare(url) == .orderedSame }
    }

    private func addDirectoryStation(_ directoryStation: RadioDirectoryStation) {
        guard let url = directoryStation.preferredStreamURL?.absoluteString else { return }
        guard !isStationAlreadyAdded(directoryStation) else { return }

        let station = RadioStation(
            name: directoryStation.name,
            streamURL: url,
            metadataURL: nil,
            isFavorite: false
        )
        player.appendStation(station)
        selectedStationID = station.id
    }
}

private struct ImportPayload: Codable {
    let stations: [RadioStation]
}

private struct ExportPayload: Codable {
    let version: Int
    let exportedAt: Date
    let stations: [RadioStation]
}

private struct StationEditor: View {
    @Binding var station: RadioStation
    let onSave: (RadioStation) -> Void
    let onPlay: (RadioStation) -> Void

    var body: some View {
        Form {
            LabeledContent("Station Details", value: "")
                            .font(.headline)
            Section {
                TextField("Name:", text: $station.name)
                TextField("Stream URL:", text: $station.streamURL)
                    .textContentType(.URL)
                TextField("Metadata API URL (optional):", text: Binding(
                    get: { station.metadataURL ?? "" },
                    set: { station.metadataURL = $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
                ))
                Toggle("Favorite", isOn: $station.isFavorite)
            }
            
            Section {
                HStack {
                    Button("Save") {
                        onSave(station)
                    }
                    Spacer()
                    Button("Save & Play") {
                        onSave(station)
                        onPlay(station)
                    }
                }
            }
        }
//        .formStyle(.columns)
        .formStyle(.grouped)
//        .formStyle(.automatic)
}
}
