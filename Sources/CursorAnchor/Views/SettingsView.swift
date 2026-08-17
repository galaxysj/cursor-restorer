import SwiftUI

struct SettingsView: View {
    @ObservedObject var tracker: CursorTrackingStore
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

            Section("Keyboard shortcuts") {
                LabeledContent("Restore") {
                    ShortcutRecorder(shortcut: tracker.restoreShortcut) {
                        tracker.updateRestoreShortcut($0)
                    }
                    .frame(width: 158, height: 30)
                    .id("restore-shortcut-recorder")
                }

                LabeledContent("Start / stop") {
                    ShortcutRecorder(shortcut: tracker.toggleShortcut) {
                        tracker.updateToggleShortcut($0)
                    }
                    .frame(width: 158, height: 30)
                    .id("toggle-shortcut-recorder")
                }

                Text("Click a shortcut, then press a new key combination. Both shortcuts work in the background.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Button("Reset shortcuts") {
                    tracker.resetShortcuts()
                }
            }
        }
        .formStyle(.grouped)
        .scenePadding()
        .frame(width: 500, height: 360)
    }
}
