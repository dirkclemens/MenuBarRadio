import SwiftUI

/// Editor form for a single station entry.
struct StationEditor: View {
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
        .formStyle(.grouped)
    }
}
