import AppKit
import SwiftUI

/// Directory search tab with pre-listen and add actions.
struct SettingsDirectoryTabView: View {
    @EnvironmentObject private var player: RadioPlayer
    @ObservedObject var directory: RadioDirectoryController
    @Binding var wasPlayingBeforePreview: Bool
    let onAddStation: (RadioDirectoryStation) -> Void
    let isStationAlreadyAdded: (RadioDirectoryStation) -> Bool
    let detailLine: (RadioDirectoryStation) -> String

    var body: some View {
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
                Button {
                    Task { await directory.search() }
                } label: {
                    Text("Search")
                    Image(systemName: "magnifyingglass.circle")
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
                        Text(detailLine(station))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        if let streamURL = station.preferredStreamURL {
                            HStack(spacing: 6) {
                                Link(streamURL.absoluteString, destination: streamURL)
                                    .font(.caption2)
                                    .foregroundStyle(.blue)
                                    .lineLimit(1)
                                Button {
                                    let pasteboard = NSPasteboard.general
                                    pasteboard.clearContents()
                                    pasteboard.setString(streamURL.absoluteString, forType: .string)
                                } label: {
                                    Image(systemName: "doc.on.doc")
                                }
                                .buttonStyle(.plain)
                                .help("Copy URL")
                            }
                        }
                    }
                    .textSelection(.enabled)
                    Spacer(minLength: 0)
                    Spacer()
                    Button {
                        if directory.previewingStationID == station.id {
                            directory.togglePreview(for: station)
                            if wasPlayingBeforePreview {
                                player.play()
                            }
                        } else {
                            wasPlayingBeforePreview = player.isPlaying
                            player.pause()
                            directory.togglePreview(for: station)
                        }
                    } label: {
                        Image(systemName: directory.previewingStationID == station.id ? "stop.circle" : "play.circle")
                    }
                    .disabled(station.preferredStreamURL == nil)

                    Button {
                        onAddStation(station)
                    } label: {
                        Image(systemName: "plus.circle")
                    }
                    .disabled(isStationAlreadyAdded(station) || station.preferredStreamURL == nil)
                }
            }
        }
    }
}
