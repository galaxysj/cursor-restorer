import AppKit
import Carbon.HIToolbox

/// Registers ⌘⇧R with macOS so the shortcut is delivered even when another
/// application owns the focused window.
final class GlobalShortcutMonitor {
    private static let hotKeySignature: OSType = 0x43555253 // "CURS"
    private static let hotKeyID: UInt32 = 1

    private let action: () -> Void
    private var eventHandler: EventHandlerRef?
    private var hotKey: EventHotKeyRef?

    private static let eventHandlerCallback: EventHandlerUPP = { _, _, userData in
        guard let userData else {
            return noErr
        }

        let monitor = Unmanaged<GlobalShortcutMonitor>
            .fromOpaque(userData)
            .takeUnretainedValue()
        monitor.fire()
        return noErr
    }

    init(action: @escaping () -> Void) {
        self.action = action
        register()
    }

    deinit {
        unregister()
    }

    private func register() {
        let target = GetEventDispatcherTarget()
        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let userData = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())

        let handlerStatus = InstallEventHandler(
            target,
            Self.eventHandlerCallback,
            1,
            &eventSpec,
            userData,
            &eventHandler
        )

        guard handlerStatus == noErr else {
            return
        }

        let hotKeyID = EventHotKeyID(
            signature: Self.hotKeySignature,
            id: Self.hotKeyID
        )
        let modifiers = UInt32(cmdKey | shiftKey)
        let registrationStatus = RegisterEventHotKey(
            UInt32(kVK_ANSI_R),
            modifiers,
            hotKeyID,
            target,
            0,
            &hotKey
        )

        guard registrationStatus == noErr else {
            if let eventHandler {
                RemoveEventHandler(eventHandler)
            }
            self.eventHandler = nil
            return
        }
    }

    private func unregister() {
        if let hotKey {
            UnregisterEventHotKey(hotKey)
        }

        if let eventHandler {
            RemoveEventHandler(eventHandler)
        }

        hotKey = nil
        eventHandler = nil
    }

    private func fire() {
        let action = self.action
        DispatchQueue.main.async {
            action()
        }
    }
}
