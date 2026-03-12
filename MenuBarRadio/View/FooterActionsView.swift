import SwiftUI

/// Footer actions row (settings + quit).
struct FooterActionsView: View {
    var body: some View {
        HStack {
            SettingsLink {
                Image(systemName: "gear")
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
}
