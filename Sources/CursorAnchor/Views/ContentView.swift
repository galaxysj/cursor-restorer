import SwiftUI

struct ContentView: View {
    @ObservedObject var tracker: CursorTrackingStore
    @AppStorage("appearanceMode") private var appearanceMode = AppearanceMode.system.rawValue

    private var selectedAppearance: AppearanceMode {
        AppearanceMode(rawValue: appearanceMode) ?? .system
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Divider()
                .padding(.top, 22)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    trackingCard
                    accessibilityCard
                    shortcutCard
                }
                .padding(.top, 20)
                .padding(.bottom, 4)
            }
        }
        .padding(28)
        .frame(minWidth: 620, minHeight: 540)
        .background(.regularMaterial)
        .preferredColorScheme(selectedAppearance.colorScheme)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    tracker.restoreSavedPosition()
                } label: {
                    Label("Restore", systemImage: "arrow.uturn.backward.circle")
                }
                .disabled(!tracker.hasSavedPosition)
                .help("Restore the saved cursor position (⌘⇧R)")

                Button {
                    tracker.toggleTracking()
                } label: {
                    Label(
                        tracker.isTracking ? "Stop" : "Start",
                        systemImage: tracker.isTracking ? "stop.fill" : "play.fill"
                    )
                }
                .help(tracker.isTracking ? "Stop cursor tracking" : "Start cursor tracking")
            }
        }
        .onAppear {
            tracker.refreshAccessibilityStatus()
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "cursorarrow.rays")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(.tint)
                .frame(width: 52, height: 52)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))

            VStack(alignment: .leading, spacing: 4) {
                Text("Cursor Restorer")
                    .font(.title2.weight(.semibold))

                Text("Save a calm moment. Return to it instantly.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            StatusBadge(
                title: tracker.isTracking ? "Tracking" : "Paused",
                tint: tracker.isTracking ? .green : .secondary
            )
        }
    }

    private var trackingCard: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Label("Cursor tracking", systemImage: "dot.scope")
                    .font(.headline)

                Spacer()

                Text(tracker.idleStatusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text("Cursor Restorer checks the pointer continuously and saves its position once it stays still for more than one second.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 12) {
                Button(tracker.isTracking ? "Stop tracking" : "Start tracking") {
                    tracker.toggleTracking()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Text(tracker.statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Divider()
                .padding(.vertical, 2)

            savedPositionSection
        }
        .cardStyle()
    }

    private var savedPositionSection: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Label("Saved position", systemImage: tracker.hasSavedPosition ? "checkmark.circle.fill" : "circle.dashed")
                    .font(.headline)
                    .foregroundStyle(tracker.hasSavedPosition ? .green : .primary)

                Spacer()

                if tracker.hasSavedPosition {
                    Button("Clear") {
                        tracker.clearSavedPosition()
                    }
                    .buttonStyle(.borderless)
                }
            }

            if let savedPosition = tracker.savedPosition {
                HStack(alignment: .firstTextBaseline) {
                    Text(CursorTrackingStore.positionText(savedPosition))
                        .font(.system(.title3, design: .monospaced).weight(.medium))

                    Text("screen coordinates")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button("Restore now") {
                        tracker.restoreSavedPosition()
                    }
                    .buttonStyle(.bordered)
                }
            } else {
                Text("Nothing saved yet. Start tracking and leave the cursor still for one second.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var accessibilityCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: tracker.accessibilityTrusted ? "checkmark.shield.fill" : "lock.shield")
                .font(.title3)
                .foregroundStyle(tracker.accessibilityTrusted ? .green : .orange)

            VStack(alignment: .leading, spacing: 4) {
                Text(tracker.accessibilityTrusted ? "Accessibility access granted" : "Accessibility access needed")
                    .font(.headline)

                Text("macOS requires this permission before the app can move the cursor back to a saved position.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            if !tracker.accessibilityTrusted {
                Button("Open System Settings") {
                    tracker.openAccessibilitySettings()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .cardStyle()
    }

    private var shortcutCard: some View {
        HStack(spacing: 13) {
            Image(systemName: "keyboard")
                .font(.title3)
                .foregroundStyle(.tint)

            VStack(alignment: .leading, spacing: 3) {
                Text("Restore shortcut")
                    .font(.headline)

                Text("Works while Cursor Restorer is in the background.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            ShortcutKeys()
        }
        .cardStyle()
    }
}

private struct StatusBadge: View {
    let title: String
    let tint: Color

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(tint)
                .frame(width: 7, height: 7)

            Text(title)
                .font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.thinMaterial, in: Capsule())
        .overlay(Capsule().stroke(.quaternary))
    }
}

private struct ShortcutKeys: View {
    var body: some View {
        HStack(spacing: 4) {
            KeyCap("⌘")
            KeyCap("⇧")
            KeyCap("R")
        }
    }
}

private struct KeyCap: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.system(.caption, design: .rounded).weight(.semibold))
            .frame(minWidth: 24, minHeight: 23)
            .padding(.horizontal, 3)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(.quaternary))
    }
}

private extension View {
    func cardStyle() -> some View {
        self
            .padding(17)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(.quaternary)
            )
    }
}
