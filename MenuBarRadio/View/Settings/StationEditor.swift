import SwiftUI

/// Editor form for a single station entry.
struct StationEditor: View {
    @Binding var station: RadioStation
    let isRefreshing: Bool
    let onSave: (RadioStation) -> Void
    let onPlay: (RadioStation) -> Void
    let onRefresh: (RadioStation) -> Void

    var body: some View {
        Form {
            LabeledContent("Station Details", value: "")
                .font(.headline)

            Section {
                HStack {
                    Button(isRefreshing ? "Refreshing…" : "Refresh Details") {
                        onRefresh(station)
                    }
                    .disabled(isRefreshing)
                    Spacer()
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
                VStack(alignment: .leading, spacing: 6) {
                    LabeledContent("Bitrate") {
                        if let bitrate = station.bitrate {
                            Text("\(bitrate) kbps")
                        } else {
                            Text("—")
                        }
                    }
                    LabeledContent("Codec") {
                        Text(displayText(station.codec))
                    }
                    LabeledContent("Votes") {
                        if let votes = station.votes {
                            Text("\(votes)")
                        } else {
                            Text("—")
                        }
                    }
                    LabeledContent("Country") {
                        Text("\(displayText(station.country)) - \(displayText(station.countryCode))")
                    }
                    LabeledContent("State") {
                        Text(displayText(station.state))
                    }
                    LabeledContent("Language") {
                        Text("\(displayText(station.language)) - \(displayText(station.languageCodes))")
                    }
                    LabeledContent("Homepage") {
                        if let url = station.homepageURL {
                            Link(url.absoluteString, destination: url)
                        } else {
                            Text("—")
                        }
                    }
                    LabeledContent("Favicon") {
                        if let url = station.faviconURL {
                            HStack(spacing: 8) {
                                AsyncImage(url: url) { phase in
                                    switch phase {
                                    case .empty:
                                        ProgressView()
                                            .controlSize(.small)
                                    case .success(let image):
                                        image
                                            .resizable()
                                            .scaledToFit()
                                    case .failure:
                                        Image(systemName: "photo")
                                            .foregroundStyle(.secondary)
                                    @unknown default:
                                        Image(systemName: "photo")
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .frame(width: 18, height: 18)
                                Link(url.absoluteString, destination: url)
                                    .lineLimit(1)
                                    .textSelection(.enabled)
                            }
                        } else {
                            Text("—")
                        }
                    }
                    LabeledContent("Geo Lat/Lon") {
                        if let mapURL = appleMapsURL() {
                            Link("\(doubleText(station.geoLatitude)),\(doubleText(station.geoLongitude))", destination: mapURL)
                                .textSelection(.enabled)
                                .contextMenu {
                                    Button("Copy \(doubleText(station.geoLatitude)),\(doubleText(station.geoLongitude))") {
                                        copyToClipboard("\(doubleText(station.geoLatitude)),\(doubleText(station.geoLongitude))")
                                    }
                                }
                        } else {
                            Text("\(doubleText(station.geoLatitude)),\(doubleText(station.geoLongitude))")
                                .textSelection(.enabled)
                        }
                    }
                }
            }
            .textSelection(.enabled)
        }
        .formStyle(.grouped)
    }

    private func copyToClipboard(_ string: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
    }
    
    private func displayText(_ value: String?) -> String {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "—" : trimmed
    }

    private func doubleText(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(format: "%.5f", value)
    }

    private func appleMapsURL() -> URL? {
        guard let lat = station.geoLatitude, let lon = station.geoLongitude else { return nil }
        let urlString = "http://maps.apple.com/?ll=\(lat),\(lon)"
        return URL(string: urlString)
    }
}
