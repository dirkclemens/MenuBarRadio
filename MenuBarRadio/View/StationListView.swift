import SwiftUI

/// Scrollable list of stations with quick play/favorite actions.
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
                                    faviconView(for: station, isSelected: player.currentStation?.id == station.id)
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
            .frame(height: min(CGFloat(sortedStations.count), 6) * 34)
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

    @ViewBuilder
    private func faviconView(for station: RadioStation, isSelected: Bool) -> some View {
        if let url = station.faviconURL {
            AsyncImage(url: url) { phase in
                switch phase {
                case .empty:
                    Color.clear
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFit()
                case .failure:
                    Image(systemName: isSelected ? "dot.radiowaves.left.and.right" : "radio")
                        .foregroundStyle(.secondary)
                @unknown default:
                    Image(systemName: isSelected ? "dot.radiowaves.left.and.right" : "radio")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 16, height: 16)
        } else {
            Image(systemName: isSelected ? "dot.radiowaves.left.and.right" : "radio")
                .foregroundStyle(.secondary)
        }
    }
}
