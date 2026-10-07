import Carbon
import Foundation
import LiteKeyCore

/// Tracks the system input source (TIS) on main, outside the tap callback:
/// - the current input source's language (for turning Vietnamese off when it is not English)
/// - the key map for non-US layout compatibility (read with UCKeyTranslate once per change)
///
/// Both are computed ahead of time so the callback only does array lookups.
public final class InputSourceMonitor: NSObject {
    public private(set) var isEnglish = true
    public private(set) var layoutMap = KeyboardLayoutMap()
    /// The system input source changed (called on main)
    public var onChange: (() -> Void)?

    public override init() {
        super.init()
        refresh()
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(inputSourceChanged),
            name: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String), object: nil)
    }

    deinit {
        DistributedNotificationCenter.default().removeObserver(self)
    }

    @objc private func inputSourceChanged() {
        // This notification may arrive on another thread
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.refresh()
            self.onChange?()
        }
    }

    private func refresh() {
        isEnglish = Self.currentLanguageIsEnglish()
        layoutMap = Self.currentLayoutMap()
    }

    /// English means the input source's first language is "en"
    static func currentLanguageIsEnglish() -> Bool {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let pointer = TISGetInputSourceProperty(source, kTISPropertyInputSourceLanguages) else { return true }
        let languages = Unmanaged<CFArray>.fromOpaque(pointer).takeUnretainedValue() as? [String] ?? []
        guard let first = languages.first else { return true }
        return first == "en"
    }

    static func currentLayoutMap() -> KeyboardLayoutMap {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return KeyboardLayoutMap()
        }
        let data = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue()
        guard let bytes = CFDataGetBytePtr(data) else { return KeyboardLayoutMap() }
        let keyboardType = UInt32(LMGetKbdType())
        let shiftState = UInt32((shiftKey >> 8) & 0xFF)
        return bytes.withMemoryRebound(to: UCKeyboardLayout.self, capacity: 1) { layout in
            KeyboardLayoutMap { keyCode, shift in
                var deadKeyState: UInt32 = 0
                var length = 0
                var chars = [UniChar](repeating: 0, count: 4)
                let status = UCKeyTranslate(layout, keyCode, UInt16(kUCKeyActionDown),
                                            shift ? shiftState : 0, keyboardType,
                                            OptionBits(1 << kUCKeyTranslateNoDeadKeysBit),
                                            &deadKeyState, chars.count, &length, &chars)
                guard status == OSStatus(noErr), length > 0 else { return nil }
                return String(utf16CodeUnits: chars, count: length)
            }
        }
    }
}
