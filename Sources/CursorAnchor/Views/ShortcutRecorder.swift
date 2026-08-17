import AppKit
import Carbon.HIToolbox
import SwiftUI

struct ShortcutRecorder: NSViewRepresentable {
    let shortcut: CursorShortcut
    let onChange: (CursorShortcut) -> Void

    func makeNSView(context: Context) -> ShortcutRecorderControl {
        let view = ShortcutRecorderControl(shortcut: shortcut)
        view.onChange = onChange
        return view
    }

    func updateNSView(_ nsView: ShortcutRecorderControl, context: Context) {
        nsView.shortcut = shortcut
        nsView.onChange = onChange
    }
}

final class ShortcutRecorderControl: NSView {
    var shortcut: CursorShortcut {
        didSet {
            needsDisplay = true
        }
    }

    var onChange: ((CursorShortcut) -> Void)?

    private var isRecording = false {
        didSet {
            needsDisplay = true
        }
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 158, height: 30)
    }

    init(shortcut: CursorShortcut) {
        self.shortcut = shortcut
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func mouseDown(with event: NSEvent) {
        guard window?.makeFirstResponder(self) == true else {
            return
        }

        isRecording = true
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }

        if event.keyCode == UInt16(kVK_Escape) {
            stopRecording()
            return
        }

        capture(event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isRecording else {
            return super.performKeyEquivalent(with: event)
        }

        capture(event)
        return true
    }

    override func cancelOperation(_ sender: Any?) {
        stopRecording()
    }

    override func resignFirstResponder() -> Bool {
        stopRecording()
        return super.resignFirstResponder()
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let bounds = self.bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: bounds, xRadius: 7, yRadius: 7)

        let fillColor = isRecording
            ? NSColor.controlAccentColor.withAlphaComponent(0.16)
            : NSColor.controlBackgroundColor
        fillColor.setFill()
        path.fill()

        let strokeColor = isRecording
            ? NSColor.controlAccentColor
            : NSColor.separatorColor
        strokeColor.setStroke()
        path.lineWidth = isRecording ? 2 : 1
        path.stroke()

        let title = isRecording ? "Press shortcut…" : shortcut.displayString
        let textColor = isRecording ? NSColor.controlAccentColor : NSColor.labelColor
        let font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor
        ]
        let textSize = (title as NSString).size(withAttributes: attributes)
        let textPoint = NSPoint(
            x: bounds.midX - (textSize.width / 2),
            y: bounds.midY - (textSize.height / 2) + 1
        )
        (title as NSString).draw(at: textPoint, withAttributes: attributes)
    }

    private func capture(_ event: NSEvent) {
        guard let newShortcut = CursorShortcut(event: event) else {
            NSSound.beep()
            return
        }

        shortcut = newShortcut
        isRecording = false
        onChange?(newShortcut)
        window?.makeFirstResponder(nil)
    }

    private func stopRecording() {
        guard isRecording else {
            return
        }

        isRecording = false
        window?.makeFirstResponder(nil)
    }
}
