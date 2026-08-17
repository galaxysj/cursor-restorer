import AppKit
import Carbon.HIToolbox
import CoreGraphics
import OSLog

/// Registers a global ⌘⇧ keyboard shortcut with macOS so it is delivered even
/// when another application owns the focused window.
final class GlobalShortcutMonitor {
    private static let hotKeySignature: OSType = 0x43555253 // "CURS"
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.cursorrestorer.CursorRestorer",
        category: "Hotkeys"
    )

    private let action: () -> Void
    private var keyCode: UInt32
    private var modifiers: UInt32
    private let hotKeyID: UInt32
    private var eventHandler: EventHandlerRef?
    private var hotKey: EventHotKeyRef?
    private var eventTap: CFMachPort?
    private var eventTapSource: CFRunLoopSource?
    private var lastFireAt = 0.0

    private static let eventHandlerCallback: EventHandlerUPP = { _, event, userData in
        guard let event, let userData else {
            return noErr
        }

        let monitor = Unmanaged<GlobalShortcutMonitor>
            .fromOpaque(userData)
            .takeUnretainedValue()

        var pressedHotKeyID = EventHotKeyID()
        let parameterStatus = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &pressedHotKeyID
        )

        guard parameterStatus == noErr else {
            GlobalShortcutMonitor.logger.error("Hotkey event parameter read failed: \(parameterStatus, privacy: .public)")
            return noErr
        }

        guard pressedHotKeyID.signature == GlobalShortcutMonitor.hotKeySignature,
              pressedHotKeyID.id == monitor.hotKeyID else {
            return noErr
        }

        monitor.fire()
        return noErr
    }

    private static let eventTapCallback: CGEventTapCallBack = { _, type, event, userInfo in
        guard let userInfo else {
            return Unmanaged.passUnretained(event)
        }

        let monitor = Unmanaged<GlobalShortcutMonitor>
            .fromOpaque(userInfo)
            .takeUnretainedValue()
        return monitor.handleEventTap(type: type, event: event)
    }

    init(shortcut: CursorShortcut, hotKeyID: UInt32, action: @escaping () -> Void) {
        self.keyCode = shortcut.keyCode
        self.modifiers = shortcut.modifiers
        self.hotKeyID = hotKeyID
        self.action = action
        register()
    }

    deinit {
        unregister()
    }

    @discardableResult
    private func register() -> Bool {
        let carbonRegistered = registerCarbonHotKey()
        let eventTapRegistered = installEventTap()

        guard carbonRegistered || eventTapRegistered else {
            return false
        }

        return true
    }

    @discardableResult
    private func registerCarbonHotKey() -> Bool {
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
            Self.logger.error("Hotkey \(self.hotKeyID, privacy: .public) event handler install failed: \(handlerStatus, privacy: .public)")
            return false
        }

        let eventHotKeyID = EventHotKeyID(
            signature: Self.hotKeySignature,
            id: self.hotKeyID
        )
        let registrationStatus = RegisterEventHotKey(
            keyCode,
            modifiers,
            eventHotKeyID,
            target,
            0,
            &hotKey
        )

        guard registrationStatus == noErr else {
            if let eventHandler {
                RemoveEventHandler(eventHandler)
            }
            self.eventHandler = nil
            Self.logger.error("Hotkey \(self.hotKeyID, privacy: .public) registration failed: \(registrationStatus, privacy: .public)")
            return false
        }

        Self.logger.info("Hotkey \(self.hotKeyID, privacy: .public) registered (key code \(self.keyCode, privacy: .public), modifiers \(self.modifiers, privacy: .public))")
        return true
    }

    @discardableResult
    private func installEventTap() -> Bool {
        guard eventTap == nil else {
            return true
        }

        if !CGPreflightListenEventAccess() {
            _ = CGRequestListenEventAccess()
        }

        let eventMask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        let userData = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        guard let eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: eventMask,
            callback: Self.eventTapCallback,
            userInfo: userData
        ) else {
            Self.logger.error("Event tap unavailable for hotkey \(self.hotKeyID, privacy: .public); relying on Carbon")
            return false
        }

        guard let source = CFMachPortCreateRunLoopSource(
            kCFAllocatorDefault,
            eventTap,
            0
        ) else {
            CFMachPortInvalidate(eventTap)
            Self.logger.error("Event tap run loop source failed for hotkey \(self.hotKeyID, privacy: .public)")
            return false
        }

        self.eventTap = eventTap
        self.eventTapSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, CFRunLoopMode.commonModes)
        Self.logger.info("Event tap enabled for hotkey \(self.hotKeyID, privacy: .public)")
        return true
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

        if let eventTapSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), eventTapSource, CFRunLoopMode.commonModes)
        }

        if let eventTap {
            CFMachPortInvalidate(eventTap)
        }

        eventTapSource = nil
        eventTap = nil
    }

    func ensureEventTap() {
        _ = installEventTap()
    }

    @discardableResult
    func update(to shortcut: CursorShortcut) -> Bool {
        let previousKeyCode = keyCode
        let previousModifiers = modifiers

        unregister()
        keyCode = shortcut.keyCode
        modifiers = shortcut.modifiers

        guard register() else {
            keyCode = previousKeyCode
            modifiers = previousModifiers
            _ = register()
            return false
        }

        return true
    }

    private func fire() {
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastFireAt > 0.15 else {
            return
        }

        lastFireAt = now
        Self.logger.info("Hotkey \(self.hotKeyID, privacy: .public) fired")
        let action = self.action
        DispatchQueue.main.async {
            action()
        }
    }

    private func handleEventTap(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent> {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        guard type == .keyDown,
              event.getIntegerValueField(.keyboardEventAutorepeat) == 0 else {
            return Unmanaged.passUnretained(event)
        }

        let keyCode = UInt32(event.getIntegerValueField(.keyboardEventKeycode))
        let eventModifiers = Self.carbonModifiers(for: event.flags)

        guard keyCode == self.keyCode,
              eventModifiers == self.modifiers else {
            return Unmanaged.passUnretained(event)
        }

        fire()
        return Unmanaged.passUnretained(event)
    }

    private static func carbonModifiers(for flags: CGEventFlags) -> UInt32 {
        var modifiers: UInt32 = 0

        if flags.contains(.maskCommand) {
            modifiers |= UInt32(cmdKey)
        }
        if flags.contains(.maskAlternate) {
            modifiers |= UInt32(optionKey)
        }
        if flags.contains(.maskControl) {
            modifiers |= UInt32(controlKey)
        }
        if flags.contains(.maskShift) {
            modifiers |= UInt32(shiftKey)
        }

        return modifiers
    }
}
