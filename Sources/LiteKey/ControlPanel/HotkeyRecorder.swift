import AppKit
import LiteKeyCore
import SwiftUI

/// Hotkey recorder field: click it, then press a key.
/// Modifiers held while pressing (⌥Z) are recorded into the ⌃ ⌥ ⌘ ⇧ checkboxes; with none held the
/// checked ones are used, and with none checked the key is rejected (`Hotkey.recording`). Delete/Forward
/// Delete clear the key (modifier-only hotkey), unless that leaves fewer than two keys (`Hotkey.clearingKey`). While recording, the pipeline is suspended
/// (`onRecording(true)`) so keys are neither transformed nor treated as the hotkey.
struct HotkeyRecorder: NSViewRepresentable {
    @Binding var hotkey: Hotkey
    var onRecording: (Bool) -> Void

    func makeNSView(context: Context) -> RecorderView {
        let view = RecorderView()
        updateNSView(view, context: context)
        return view
    }

    func updateNSView(_ view: RecorderView, context: Context) {
        view.onKey = { code, held in record(code, held: held) }
        view.onRecording = onRecording
        view.keyCode = hotkey.keyCode
    }

    private func record(_ code: UInt16?, held: ModifierFlags) {
        guard let code else {
            if let cleared = hotkey.clearingKey() { hotkey = cleared } else { NSSound.beep() }
            return
        }
        if let recorded = hotkey.recording(keyCode: code, held: held) {
            hotkey = recorded
        } else {
            NSSound.beep()
        }
    }

    final class RecorderView: NSView {
        var onKey: ((UInt16?, ModifierFlags) -> Void)?
        var onRecording: ((Bool) -> Void)?
        var keyCode: UInt16? { didSet { needsDisplay = true } }
        private var recording = false { didSet { needsDisplay = true } }
        /// Accepts focus only when clicked. If the field took focus on its own (window just opened, Tab key),
        /// typing would be suspended without the user noticing: no Vietnamese marks in any app.
        private var armed = false

        override var acceptsFirstResponder: Bool { armed }
        override var canBecomeKeyView: Bool { false }
        override var intrinsicContentSize: NSSize { NSSize(width: 64, height: 22) }

        override func mouseDown(with event: NSEvent) {
            armed = true
            if window?.makeFirstResponder(self) != true { armed = false }
        }

        override func becomeFirstResponder() -> Bool {
            guard armed else { return false }
            recording = true
            onRecording?(true)
            return true
        }

        override func resignFirstResponder() -> Bool {
            armed = false
            if recording {
                recording = false
                onRecording?(false)
            }
            return true
        }

        /// Stop recording when the window loses key status (app switch, window closed) so typing resumes
        override func viewWillMove(toWindow newWindow: NSWindow?) {
            super.viewWillMove(toWindow: newWindow)
            if let window {
                NotificationCenter.default.removeObserver(self, name: NSWindow.didResignKeyNotification, object: window)
            }
            if let newWindow {
                NotificationCenter.default.addObserver(self, selector: #selector(windowDidResignKey(_:)),
                                                       name: NSWindow.didResignKeyNotification, object: newWindow)
            }
        }

        @objc private func windowDidResignKey(_ note: Notification) {
            guard recording else { return }
            window?.makeFirstResponder(nil)
        }

        override func keyDown(with event: NSEvent) {
            switch event.keyCode {
            case 51, 117: // Delete, Forward Delete
                onKey?(nil, [])
            case 53, 36, 48: // Esc, Return, Tab: cancel recording
                window?.makeFirstResponder(nil)
                return
            default:
                // NSEvent.ModifierFlags shares bit values with CGEventFlags/ModifierFlags
                onKey?(event.keyCode, ModifierFlags(rawValue: UInt64(event.modifierFlags.rawValue)))
            }
            window?.makeFirstResponder(nil)
        }

        override func draw(_ dirtyRect: NSRect) {
            let box = bounds.insetBy(dx: 1, dy: 1)
            let path = NSBezierPath(roundedRect: box, xRadius: 6, yRadius: 6)
            NSColor.textBackgroundColor.setFill()
            path.fill()
            (recording ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke()
            path.lineWidth = recording ? 2 : 1
            path.stroke()
            let text = recording ? "…" : (keyCode.map(KeyNames.name(for:)) ?? "")
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 12),
                .foregroundColor: NSColor.labelColor,
            ]
            let string = NSAttributedString(string: text, attributes: attributes)
            let size = string.size()
            string.draw(at: NSPoint(x: box.midX - size.width / 2, y: box.midY - size.height / 2))
        }
    }
}
