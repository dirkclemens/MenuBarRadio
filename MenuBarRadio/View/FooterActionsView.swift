import SwiftUI

struct FooterActionsView: View {
    var body: some View {
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
}
