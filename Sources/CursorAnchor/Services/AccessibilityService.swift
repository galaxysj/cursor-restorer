import ApplicationServices
import AppKit
import CoreGraphics

enum AccessibilityService {
    static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    static var isInputMonitoringTrusted: Bool {
        CGPreflightListenEventAccess()
    }

    static func requestAccess() {
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [promptKey: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    static func requestInputMonitoringAccess() {
        _ = CGRequestListenEventAccess()
    }

    static func openSystemSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }

        NSWorkspace.shared.open(url)
    }

    static func openInputMonitoringSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") else {
            return
        }

        NSWorkspace.shared.open(url)
    }
}
