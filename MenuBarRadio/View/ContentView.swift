import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HeaderView()
            MetadataView()
            VolumeView()
            StationListView()
            FooterActionsView()
        }
        .padding(14)
        .frame(width: 360)
    }
}
