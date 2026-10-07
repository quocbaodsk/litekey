/// Telex compatibility on other keyboard layouts.
///
/// Each key's character on the current layout is mapped back to a US key code. The characters are read
/// once per layout change (macOS layer, outside the callback) into a `KeyboardLayoutMap`; the callback only
/// does an array lookup.
public enum LayoutCompat {
    /// Character → US key code
    public static let usKeyCodes: [Character: UInt16] = [
        // Number row
        "`": 50, "~": 50, "1": 18, "!": 18, "2": 19, "@": 19, "3": 20, "#": 20, "4": 21, "$": 21,
        "5": 23, "%": 23, "6": 22, "^": 22, "7": 26, "&": 26, "8": 28, "*": 28, "9": 25, "(": 25,
        "0": 29, ")": 29, "-": 27, "_": 27, "=": 24, "+": 24,
        // Top row
        "q": 12, "w": 13, "e": 14, "r": 15, "t": 17, "y": 16, "u": 32, "i": 34, "o": 31, "p": 35,
        "[": 33, "{": 33, "]": 30, "}": 30, "\\": 42, "|": 42,
        // Home row
        "a": 0, "s": 1, "d": 2, "f": 3, "g": 5, "h": 4, "j": 38, "k": 40, "l": 37,
        ";": 41, ":": 41, "'": 39, "\"": 39,
        // Bottom row
        "z": 6, "x": 7, "c": 8, "v": 9, "b": 11, "n": 45, "m": 46,
        ",": 43, "<": 43, ".": 47, ">": 47, "/": 44, "?": 44,
    ]

    /// US key code for a key's character string (modifiers other than Shift removed): lowercased, then
    /// looked up.
    public static func usKeyCode(for keyString: String) -> UInt16? {
        let lower = keyString.lowercased()
        guard lower.count == 1, let ch = lower.first else { return nil }
        return usKeyCodes[ch]
    }

    /// Unshifted character of a key code on the US layout
    public static func usCharacter(for keyCode: UInt16) -> Character? {
        unshiftedUS[keyCode]
    }

    private static let unshiftedUS: [UInt16: Character] = {
        var table: [UInt16: Character] = [:]
        for ch in "`1234567890-=qwertyuiop[]\\asdfghjkl;'zxcvbnm,./" {
            if let code = usKeyCodes[ch] { table[code] = ch }
        }
        return table
    }()
}

/// Physical key code → US key code for the current layout, precomputed outside the callback.
public struct KeyboardLayoutMap: Equatable, Sendable {
    public static let count = 128
    /// `noMapping` = keep the original key code
    public static let noMapping: UInt16 = 0xFFFF

    private var unshifted: [UInt16]
    private var shifted: [UInt16]

    /// Empty map: no remapping
    public init() {
        unshifted = Array(repeating: Self.noMapping, count: Self.count)
        shifted = unshifted
    }

    /// `characters(keyCode, shift)` returns the string the current layout produces for that key.
    public init(characters: (UInt16, Bool) -> String?) {
        self.init()
        for code in 0..<Self.count {
            let key = UInt16(code)
            if let s = characters(key, false), let mapped = LayoutCompat.usKeyCode(for: s) { unshifted[code] = mapped }
            if let s = characters(key, true), let mapped = LayoutCompat.usKeyCode(for: s) { shifted[code] = mapped }
        }
    }

    public func map(_ keyCode: UInt16, shift: Bool) -> UInt16 {
        guard Int(keyCode) < Self.count else { return keyCode }
        let mapped = shift ? shifted[Int(keyCode)] : unshifted[Int(keyCode)]
        return mapped == Self.noMapping ? keyCode : mapped
    }
}
