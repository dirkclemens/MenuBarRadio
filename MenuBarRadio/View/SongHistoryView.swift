import SwiftUI

/// Recent track history list in the menu popover.
struct SongHistoryView: View {
    @EnvironmentObject private var player: RadioPlayer

    var body: some View {
        if player.songHistoryLimit > 0 {
            VStack(alignment: .leading, spacing: 6) {
                Text("Recent Tracks")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if player.songHistory.isEmpty {
                    Text("No history yet.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(player.songHistory) { entry in
                                HStack(spacing: 2) {
                                    Text("\(Self.timeFormatter.string(from: entry.playedAt)) •")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
//                                    ScrollLabelView(label: historyLine(for: entry))
                                    Text(historyLine(for: entry))
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .help(historyLine(for: entry))
                                }
                            }
                        }
                    }
                    .frame(height: min(CGFloat(player.songHistory.count), 6) * 18)
                }
            }
            .textSelection(.enabled)
        }
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    private func historyLine(for entry: SongHistoryEntry) -> String {
        var parts: [String] = []
//        parts.append(Self.timeFormatter.string(from: entry.playedAt))
        parts.append(entry.title)
        parts.append(entry.artist)
        if let album = entry.album, !album.isEmpty {
            parts.append(album)
        }
        return parts.joined(separator: " • ")
    }
}
