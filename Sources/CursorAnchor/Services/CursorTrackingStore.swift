import AppKit
import Combine
import CoreGraphics

@MainActor
final class CursorTrackingStore: ObservableObject {
    static let idleThreshold: TimeInterval = 1.0

    @Published private(set) var isTracking = false
    @Published private(set) var hasSavedPosition = false
    @Published private(set) var savedPosition: CGPoint?
    @Published private(set) var idleDuration: TimeInterval = 0
    @Published private(set) var accessibilityTrusted = false
    @Published private(set) var inputMonitoringTrusted = false
    @Published private(set) var statusMessage = "Ready to track your cursor."
    @Published private(set) var restoreShortcut: CursorShortcut
    @Published private(set) var toggleShortcut: CursorShortcut

    private static let restoreShortcutDefaultsKey = "restoreShortcut"
    private static let toggleShortcutDefaultsKey = "toggleShortcut"
    private var trackingTimer: Timer?
    private var restoreShortcutMonitor: GlobalShortcutMonitor?
    private var toggleShortcutMonitor: GlobalShortcutMonitor?
    private var lastPosition: CGPoint?
    private var lastMovementAt = Date()
    private var savedForCurrentStillness = false
    private var appActivationObserver: NSObjectProtocol?

    var idleStatusText: String {
        guard isTracking else {
            return "Tracking is paused"
        }

        if savedForCurrentStillness {
            return "Saved after 1 second of stillness"
        }

        return String(format: "Still for %.1f seconds", idleDuration)
    }

    init() {
        accessibilityTrusted = AccessibilityService.isTrusted
        inputMonitoringTrusted = AccessibilityService.isInputMonitoringTrusted
        restoreShortcut = CursorShortcut.load(
            from: Self.restoreShortcutDefaultsKey,
            fallback: .defaultRestore
        )
        toggleShortcut = CursorShortcut.load(
            from: Self.toggleShortcutDefaultsKey,
            fallback: .defaultToggle
        )

        restoreShortcutMonitor = GlobalShortcutMonitor(
            shortcut: restoreShortcut,
            hotKeyID: 1
        ) { [weak self] in
            Task { @MainActor in
                self?.restoreSavedPosition()
            }
        }

        toggleShortcutMonitor = GlobalShortcutMonitor(
            shortcut: toggleShortcut,
            hotKeyID: 2
        ) { [weak self] in
            Task { @MainActor in
                self?.toggleTracking()
            }
        }

        appActivationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshAccessibilityStatus()
            }
        }
    }

    deinit {
        trackingTimer?.invalidate()
        if let appActivationObserver {
            NotificationCenter.default.removeObserver(appActivationObserver)
        }
    }

    func toggleTracking() {
        if isTracking {
            stopTracking()
        } else {
            startTracking()
        }
    }

    func updateRestoreShortcut(_ shortcut: CursorShortcut) {
        guard shortcut != toggleShortcut else {
            statusMessage = "Restore and start/stop shortcuts must be different."
            return
        }

        guard let monitor = restoreShortcutMonitor,
              monitor.update(to: shortcut) else {
            statusMessage = "That restore shortcut is unavailable."
            return
        }

        restoreShortcut = shortcut
        shortcut.save(to: Self.restoreShortcutDefaultsKey)
        statusMessage = "Restore shortcut set to \(shortcut.displayString)."
    }

    func updateToggleShortcut(_ shortcut: CursorShortcut) {
        guard shortcut != restoreShortcut else {
            statusMessage = "Restore and start/stop shortcuts must be different."
            return
        }

        guard let monitor = toggleShortcutMonitor,
              monitor.update(to: shortcut) else {
            statusMessage = "That start/stop shortcut is unavailable."
            return
        }

        toggleShortcut = shortcut
        shortcut.save(to: Self.toggleShortcutDefaultsKey)
        statusMessage = "Start/stop shortcut set to \(shortcut.displayString)."
    }

    func resetShortcuts() {
        if restoreShortcut != .defaultRestore {
            updateRestoreShortcut(.defaultRestore)
        }
        if toggleShortcut != .defaultToggle {
            updateToggleShortcut(.defaultToggle)
        }
        statusMessage = "Keyboard shortcuts reset to defaults."
    }

    func startTracking() {
        guard !isTracking else { return }

        refreshAccessibilityStatus()
        isTracking = true
        savedForCurrentStillness = false
        lastMovementAt = Date()
        idleDuration = 0
        lastPosition = currentCursorPosition()

        trackingTimer?.invalidate()
        trackingTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.pollCursor()
            }
        }

        if accessibilityTrusted {
            statusMessage = "Watching for 1 second of stillness."
        } else {
            statusMessage = "Tracking started. Enable Accessibility to restore the cursor."
        }
    }

    func stopTracking() {
        trackingTimer?.invalidate()
        trackingTimer = nil
        isTracking = false
        idleDuration = 0

        if hasSavedPosition {
            statusMessage = "Tracking stopped. Your saved position is kept."
        } else {
            statusMessage = "Tracking stopped."
        }
    }

    func restoreSavedPosition() {
        guard let savedPosition else {
            statusMessage = "No position has been saved yet."
            return
        }

        refreshAccessibilityStatus()

        guard accessibilityTrusted else {
            statusMessage = "Accessibility access is required to restore the cursor."
            AccessibilityService.requestAccess()
            return
        }

        let result = CGWarpMouseCursorPosition(savedPosition)
        guard result == .success else {
            statusMessage = "macOS could not move the cursor. Try again."
            return
        }

        lastPosition = savedPosition
        lastMovementAt = Date()
        idleDuration = 0
        statusMessage = "Cursor restored to \(Self.positionText(savedPosition))."
    }

    func clearSavedPosition() {
        savedPosition = nil
        hasSavedPosition = false
        savedForCurrentStillness = false
        statusMessage = "Saved position cleared."
    }

    func refreshAccessibilityStatus() {
        let wasTrusted = accessibilityTrusted
        accessibilityTrusted = AccessibilityService.isTrusted
        inputMonitoringTrusted = AccessibilityService.isInputMonitoringTrusted

        if accessibilityTrusted {
            restoreShortcutMonitor?.ensureEventTap()
            toggleShortcutMonitor?.ensureEventTap()
        }

        if !wasTrusted && accessibilityTrusted {
            statusMessage = "Accessibility access granted."
        }
    }

    func openAccessibilitySettings() {
        AccessibilityService.requestAccess()
        AccessibilityService.openSystemSettings()
        statusMessage = "Enable Cursor Restorer in Accessibility, then return here."
    }

    func openInputMonitoringSettings() {
        AccessibilityService.requestInputMonitoringAccess()
        AccessibilityService.openInputMonitoringSettings()
        statusMessage = "Enable Cursor Restorer in Input Monitoring, then return here."
    }

    static func positionText(_ position: CGPoint) -> String {
        "(\(Int(position.x.rounded())), \(Int(position.y.rounded())))"
    }

    private func pollCursor() {
        guard isTracking, let currentPosition = currentCursorPosition() else { return }

        if let lastPosition, !Self.samePoint(lastPosition, currentPosition) {
            self.lastPosition = currentPosition

            lastMovementAt = Date()
            idleDuration = 0
            savedForCurrentStillness = false
            statusMessage = "Cursor moved. Waiting for stillness."
        } else if lastPosition == nil {
            lastPosition = currentPosition
            lastMovementAt = Date()
        }

        idleDuration = Date().timeIntervalSince(lastMovementAt)

        guard idleDuration >= Self.idleThreshold,
              !savedForCurrentStillness else {
            return
        }

        savedPosition = currentPosition
        hasSavedPosition = true
        savedForCurrentStillness = true
        statusMessage = "Saved \(Self.positionText(currentPosition)) after 1 second of stillness."
    }

    private func currentCursorPosition() -> CGPoint? {
        CGEvent(source: nil)?.location
    }

    private static func samePoint(_ lhs: CGPoint, _ rhs: CGPoint) -> Bool {
        abs(lhs.x - rhs.x) < 0.5 && abs(lhs.y - rhs.y) < 0.5
    }
}
