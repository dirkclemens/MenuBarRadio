import SwiftUI

/// Stations management tab (list + editor).
struct SettingsStationsTabView: View {
    @EnvironmentObject private var player: RadioPlayer
    @Binding var selectedStationID: UUID?
    let onImport: () -> Void
    let onExport: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Stations")
                        .font(.headline)
                    Spacer()
                    Button("Import") { onImport() }
                    Button("Export") { onExport() }
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

    private var selectedStationBinding: Binding<RadioStation>? {
        guard let id = selectedStationID else { return nil }
        guard let index = player.stations.firstIndex(where: { $0.id == id }) else { return nil }
        return Binding(
            get: { player.stations[index] },
            set: { player.stations[index] = $0 }
        )
    }
}
