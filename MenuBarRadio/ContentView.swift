import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var player: RadioPlayer

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            metadataView
            volumeView
            stationList
            footerActions
        }
        .padding(14)
        .frame(width: 360)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Picker("Station", selection: Binding<UUID?>(
                get: { player.currentStation?.id },
                set: { newValue in
                    guard let id = newValue else { return }
                    player.selectStation(id: id)
                }
            )) {
                ForEach(player.stations) { station in
                    Text(station.name).tag(Optional(station.id))
                }
            }
            .labelsHidden()
            .frame(maxWidth: .infinity)

            Button {
                player.togglePlayPause()
            } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .frame(width: 22)
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var metadataView: some View {
        HStack(alignment: .top, spacing: 12) {
            ArtworkView(metadata: player.nowPlaying)
            VStack(alignment: .leading, spacing: 4) {
                Text(player.nowPlaying.title ?? "No title metadata")
                    .font(.headline)
                    .lineLimit(2)
                if let album = player.nowPlaying.album, !album.isEmpty {
                    Text("Album: \(player.nowPlaying.album ?? "No album metadata")")
                        .font(.subheadline)
                        .lineLimit(2)
                }
                Text(player.nowPlaying.artist ?? "Unknown artist")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let year = player.nowPlaying.year {
                    Text("Year: \(year)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let station = player.currentStation {
                    Text(station.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var volumeView: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Volume")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Image(systemName: "speaker.fill")
                    .foregroundStyle(.secondary)
                Slider(value: Binding(
                    get: { Double(player.volume) },
                    set: { player.volume = Float($0) }
                ), in: 0...1)
                Image(systemName: "speaker.wave.3.fill")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var stationList: some View {
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

    private var footerActions: some View {
        HStack {
            SettingsLink {
                Image(systemName: "gearshape")
                    .font(.system(size: 12))
            }
            Spacer()
            Button(action: { NSApp.terminate(nil) }) {
                Image(systemName: "power")
                    .font(.system(size: 12))
            }
            .foregroundColor(.secondary)
            .help(NSLocalizedString("QuitMenuTitle", comment: ""))
        }
        .font(.caption)
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
