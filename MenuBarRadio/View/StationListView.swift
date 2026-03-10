import SwiftUI

struct StationListView: View {
    @EnvironmentObject private var player: RadioPlayer

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Stations")
                .font(.caption)
                .foregroundStyle(.secondary)

            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(sortedStations, id: \.id) { station in
                        HStack(spacing: 8) {
                            Button {
                                player.selectStation(id: station.id, autoPlay: true)
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: player.currentStation?.id == station.id ? "dot.radiowaves.left.and.right" : "radio")
                                    Text(station.name)
                                        .lineLimit(1)
                                    Spacer(minLength: 0)
                                }
                            }
                            .buttonStyle(.plain)

                            Button {
                                player.toggleFavorite(id: station.id)
                            } label: {
                                Image(systemName: station.isFavorite ? "star.fill" : "star")
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, 4)
                        .padding(.horizontal, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(player.currentStation?.id == station.id ? Color.accentColor.opacity(0.18) : Color.clear)
                        )
                    }
                }
            }
            .frame(maxHeight: min(CGFloat(sortedStations.count), 10) * 34)
        }
    }

    private func stationSort(lhs: RadioStation, rhs: RadioStation) -> Bool {
        if lhs.isFavorite != rhs.isFavorite {
            return lhs.isFavorite && !rhs.isFavorite
        }
        return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
    }

    private var sortedStations: [RadioStation] {
        player.stations.sorted(by: stationSort)
    }
}
