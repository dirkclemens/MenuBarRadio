import SwiftUI

/// Footer actions row (settings + quit).
struct FooterActionsView: View {
    var body: some View {
        HStack {
            SettingsLink {
                Image(systemName: "gear")
                    .font(.system(size: 12))
            }
            .help("Settings")
            Spacer()
            Button(action: { NSApp.terminate(nil) }) {
                Image(systemName: "power")
                    .font(.system(size: 12))
            }
            .foregroundColor(.secondary)
            .help("Quit MenuBar Radio")
        }
        .font(.caption)
    }
}
