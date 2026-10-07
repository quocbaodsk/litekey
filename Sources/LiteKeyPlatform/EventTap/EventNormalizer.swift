import CoreGraphics
import LiteKeyCore

/// Converts a CGEvent into a pure `KeyEvent`. Returns `nil` for events that need no handling,
/// including events LiteKey posted itself (recognized by `EventMarker`).
public enum EventNormalizer {
    public static func normalize(type: CGEventType, event: CGEvent) -> KeyEvent? {
        if event.getIntegerValueField(.eventSourceUserData) == EventMarker.value { return nil }
        let kind: KeyEvent.Kind
        switch type {
        case .keyDown: kind = .keyDown
        case .keyUp: kind = .keyUp
        case .flagsChanged: kind = .flagsChanged
        case .leftMouseDown, .rightMouseDown:
            return KeyEvent(kind: .mouseDown)
        case .leftMouseDragged, .rightMouseDragged:
            return KeyEvent(kind: .mouseDragged)
        default:
            return nil
        }
        let keyCode = UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode))
        let isRepeat = kind == .keyDown && event.getIntegerValueField(.keyboardEventAutorepeat) != 0
        return KeyEvent(kind: kind, keyCode: keyCode, flags: ModifierFlags(rawValue: event.flags.rawValue),
                        isRepeat: isRepeat)
    }
}
