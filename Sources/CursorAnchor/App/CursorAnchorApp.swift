import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

@main
struct CursorRestorerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var tracker: CursorTrackingStore

    init() {
        _tracker = StateObject(wrappedValue: CursorTrackingStore())
    }

    var body: some Scene {
        WindowGroup("Cursor Restorer", id: "main") {
            ContentView(tracker: tracker)
        }
        .defaultSize(width: 620, height: 540)
        .commands {
            CommandMenu("Cursor") {
                Button(tracker.isTracking ? "Stop Tracking" : "Start Tracking") {
                    tracker.toggleTracking()
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])

                Button("Restore Saved Position") {
                    tracker.restoreSavedPosition()
                }

                Divider()

                Button("Clear Saved Position") {
                    tracker.clearSavedPosition()
                }
                .disabled(!tracker.hasSavedPosition)
            }
        }

        Settings {
            SettingsView()
        }
    }
}
