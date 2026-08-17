import SwiftUI

struct SettingsView: View {
    @AppStorage("appearanceMode") private var appearanceMode = AppearanceMode.system.rawValue

    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Theme", selection: $appearanceMode) {
                    ForEach(AppearanceMode.allCases) { appearance in
                        Text(appearance.title)
                            .tag(appearance.rawValue)
                    }
                }

                Text("System follows your macOS appearance setting.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section("Keyboard") {
                LabeledContent("Restore shortcut") {
                    Text("⌘⇧R")
                        .font(.system(.body, design: .monospaced).weight(.medium))
                }

                Text("The restore shortcut works while Cursor Restorer is in the background.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .scenePadding()
        .frame(width: 460, height: 260)
    }
}
