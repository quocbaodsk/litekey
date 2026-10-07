/// Vietnamese/English switch hotkey: modifiers (⌃ ⌥ ⌘ ⇧) plus an optional regular key.
public struct Hotkey: Codable, Hashable, Sendable {
    public var modifiers: ModifierFlags
    /// `nil` = modifiers only (fires on release)
    public var keyCode: UInt16?

    public init(modifiers: ModifierFlags, keyCode: UInt16? = nil) {
        self.modifiers = modifiers.intersection(.hotkeyMask)
        self.keyCode = keyCode
    }

    public static let controlShift = Hotkey(modifiers: [.control, .shift])
    public static let controlOption = Hotkey(modifiers: [.control, .option])
    public static let controlSpace = Hotkey(modifiers: [.control], keyCode: KeyCode.space)
    /// ⌥Z (the v2 default, see `Preferences.migrated()`)
    public static let optionZ = Hotkey(modifiers: [.option], keyCode: KeyCode.z)

    public static let presets: [Hotkey] = [.controlShift, .optionZ, .controlOption, .controlSpace]

    /// Smallest number of keys (modifiers + regular key) a usable hotkey has
    public static let minimumKeys = 2

    /// Number of keys: each modifier, plus the regular key if set
    public var keyCount: Int {
        // Bit count, not a collection: `matches` runs inside the event tap callback
        modifiers.intersection(.hotkeyMask).rawValue.nonzeroBitCount + (keyCode == nil ? 0 : 1)
    }

    /// Usable as a switch hotkey: at least `minimumKeys` keys, so at least one modifier.
    ///
    /// A single key is too easy to hit: a bare letter (Z with every modifier unchecked) would make "z"
    /// untypeable, and a lone ⌃ or ⌘ would take over the "release ⌃/⌘ alone" toggles. Such a hotkey never
    /// fires, even when it comes from old or imported settings.
    public var isUsable: Bool { keyCount >= Self.minimumKeys }

    /// Whether modifier `flag` can be unchecked without dropping below `minimumKeys`
    public func canRemove(_ flag: ModifierFlags) -> Bool {
        Hotkey(modifiers: modifiers.subtracting(flag), keyCode: keyCode).isUsable
    }

    /// Result of clearing the regular key in the hotkey recorder; `nil` if the modifiers alone are too few.
    public func clearingKey() -> Hotkey? {
        let result = Hotkey(modifiers: modifiers)
        return result.isUsable ? result : nil
    }

    /// Result of recording key `code` in the hotkey recorder while holding `held`: held modifiers (if any)
    /// replace the ⌃ ⌥ ⌘ ⇧ checkboxes, otherwise the checked ones are used. `nil` if there is no modifier.
    public func recording(keyCode code: UInt16, held: ModifierFlags) -> Hotkey? {
        let heldModifiers = held.intersection(.hotkeyMask)
        let result = Hotkey(modifiers: heldModifiers.isEmpty ? modifiers : heldModifiers, keyCode: code)
        return result.isUsable ? result : nil
    }

    /// Modifiers in `flags` must match exactly, and if `keyCode` is set the key code must match too.
    public func matches(flags: ModifierFlags, keyCode code: UInt16?) -> Bool {
        guard isUsable else { return false }
        guard flags.intersection(.hotkeyMask) == modifiers else { return false }
        if let keyCode { return code == keyCode }
        return true
    }

    /// Display title, in ⌃ ⌥ ⌘ ⇧ + key order
    public var title: String {
        var parts: [String] = []
        if modifiers.contains(.control) { parts.append("⌃") }
        if modifiers.contains(.option) { parts.append("⌥") }
        if modifiers.contains(.command) { parts.append("⌘") }
        if modifiers.contains(.shift) { parts.append("⇧") }
        if let keyCode { parts.append(KeyNames.name(for: keyCode)) }
        return parts.joined(separator: " + ")
    }
}

/// Result of handling a modifier event.
public struct HotkeyFlagsResult: Equatable, Sendable {
    /// A modifiers-only switch hotkey was released: toggle mode, swallow the event
    public var toggle = false
    /// A lone ⌃ tap: toggle temporary spell-check off
    public var controlReleased = false
    /// A lone ⌘ tap: temporarily disable the engine
    public var commandReleased = false

    public init(toggle: Bool = false, controlReleased: Bool = false, commandReleased: Bool = false) {
        self.toggle = toggle
        self.controlReleased = controlReleased
        self.commandReleased = commandReleased
    }
}

/// Detects the switch hotkey.
///
/// - While modifiers are pressed, `lastFlag` keeps the largest flags; on the first release it is compared
///   with the hotkey.
/// - Hotkeys with a regular key (⌥Z) match on keyDown, using the flags of the latest modifier press.
/// - Tapping ⌃ or ⌘ alone (no other modifier or key) is reported so spell checking or the engine can be
///   turned off temporarily.
/// - Modifier releases count only as a tap: released within `maxTap` of the last press, with no click in
///   between (`cancel()`). Holding ⌃⇧ and letting go, or ⌃⇧+click, toggles nothing.
/// - Once a gesture is spoiled (a click, a key pressed while ⌃ ⌥ ⌘ are held, or a release that fires
///   nothing and leaves other modifiers down), nothing fires until every modifier is up: ⌃⇧⌥ released as
///   ⌥ then ⇧ is not ⌃⇧, and ⌃⇧A released as ⇧ then ⌃ is not a ⌃ tap.
public struct HotkeyStateMachine: Sendable {
    public var hotkey: Hotkey
    private var lastFlag: ModifierFlags = []
    private var hasJustUsedHotkey = false
    /// Uptime (ns) of the last modifier press; 0 = unknown
    private var pressedAt: UInt64 = 0
    /// The held modifiers were used for something else; cleared once all are released
    private var cancelled = false

    static let maxTap: UInt64 = 500_000_000

    public init(hotkey: Hotkey) {
        self.hotkey = hotkey
    }

    /// Returns `true` if the key is the switch hotkey (toggle mode and swallow the key).
    /// `flags`: the key's modifiers; a held ⌃ ⌥ ⌘ is now part of a shortcut, not a tap. ⇧ alone is typing a
    /// capital, so holding ⇧ and then tapping ⌃ still toggles ⌃⇧.
    public mutating func keyDown(keyCode: UInt16, flags: ModifierFlags) -> Bool {
        // A key with no shortcut modifier also clears a spoiled gesture whose final release was missed
        cancelled = !flags.isDisjoint(with: [.control, .option, .command])
        guard let switchKey = hotkey.keyCode, switchKey == keyCode else {
            lastFlag = []
            hasJustUsedHotkey = false
            return false
        }
        if hotkey.matches(flags: lastFlag, keyCode: keyCode) {
            lastFlag = []
            hasJustUsedHotkey = true
            return true
        }
        hasJustUsedHotkey = !lastFlag.isEmpty
        return false
    }

    /// The held modifiers were used for something else (mouse click): no toggle or release report until
    /// all of them are released
    public mutating func cancel() {
        if !lastFlag.isEmpty { cancelled = true }
    }

    /// `time`: event uptime in ns; 0 skips the tap-length check
    public mutating func flagsChanged(_ flags: ModifierFlags, time: UInt64 = 0) -> HotkeyFlagsResult {
        defer { if flags.isDisjoint(with: .hotkeyMask) { cancelled = false } }
        if lastFlag.isEmpty || lastFlag.rawValue < flags.rawValue {
            lastFlag = flags
            pressedAt = time
            return HotkeyFlagsResult()
        }
        guard lastFlag.rawValue > flags.rawValue else { return HotkeyFlagsResult() }

        // Release started
        let heldTooLong = time > 0 && pressedAt > 0 && time > pressedAt &+ Self.maxTap
        if !cancelled && !heldTooLong && hotkey.keyCode == nil && hotkey.matches(flags: lastFlag, keyCode: nil) {
            // Not spoiled afterwards: holding ⇧ and tapping ⌃ again toggles again
            lastFlag = []
            hasJustUsedHotkey = true
            return HotkeyFlagsResult(toggle: true)
        }
        var result = HotkeyFlagsResult()
        if !cancelled && !heldTooLong && !hasJustUsedHotkey {
            // Only a lone ⌃ or ⌘ tap; ⌃⌥ or ⌘⇧ released without a key is some other gesture
            let held = lastFlag.intersection(.hotkeyMask)
            result.controlReleased = held == .control
            result.commandReleased = held == .command
        }
        // Modifiers still down can't start a new tap until all are up
        if !flags.isDisjoint(with: .hotkeyMask) { cancelled = true }
        lastFlag = []
        hasJustUsedHotkey = false
        return result
    }
}

/// Display names for key codes (used by the hotkey recorder).
public enum KeyNames {
    public static func name(for keyCode: UInt16) -> String {
        switch keyCode {
        case KeyCode.space: return "Space"
        case KeyCode.returnKey: return "↩"
        case KeyCode.tab: return "⇥"
        case KeyCode.delete: return "⌫"
        case KeyCode.escape: return "⎋"
        default:
            if let ch = LayoutCompat.usCharacter(for: keyCode) { return String(ch).uppercased() }
            return "#\(keyCode)"
        }
    }
}
