import SwiftUI

/// Main menu popover layout composed of subviews.
struct ContentView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HeaderView()
            MetadataView()
            SongHistoryView()
            VolumeView()
            StationListView()
            FooterActionsView()
        }
        .padding(14)
        .frame(width: 360)
    }
}
