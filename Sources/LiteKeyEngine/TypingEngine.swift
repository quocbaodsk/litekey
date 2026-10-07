/// Input method. Raw values index `VietnameseEngine.processingChar`.
public enum InputType: Int, Codable, CaseIterable, Sendable {
    case telex = 0
    case vni = 1
    case simpleTelex1 = 2
    case simpleTelex2 = 3
}

/// Case state of the key just pressed.
public enum CapsState: UInt8, Sendable {
    case none = 0
    case shift = 1
    case capsLock = 2
}

/// Engine configuration.
public struct EngineConfig: Equatable, Sendable {
    public var inputType: InputType = .telex
    /// Place marks as in oà, uý (instead of òa, úy)
    public var modernOrthography = false
    public var checkSpelling = true
    /// Restore the typed keys for misspelled words (only applies when `checkSpelling` is on)
    public var restoreIfWrong = true
    /// Allow placing marks anywhere in the word
    public var freeMark = false
    /// Quick Telex: cc=ch, gg=gi, kk=kh, nn=ng, qq=qu, pp=ph, tt=th
    public var quickTelex = false
    /// Quick start consonants: f→ph, j→gi, w→qu
    public var quickStartConsonant = false
    /// Quick end consonants: g→ng, h→nh, k→ch
    public var quickEndConsonant = false
    /// Allow "z w j f" as consonants
    public var allowConsonantZFWJ = false
    /// Capitalize the first letter of a sentence
    public var upperCaseFirstChar = false
    public var useMacro = false
    /// Match macro expansion case to the typed text: "Btw" → "By the way", "BTW" → "BY THE WAY"
    public var autoCapsMacro = false

    public init(inputType: InputType = .telex,
                modernOrthography: Bool = false,
                checkSpelling: Bool = true,
                restoreIfWrong: Bool = true,
                freeMark: Bool = false,
                quickTelex: Bool = false,
                quickStartConsonant: Bool = false,
                quickEndConsonant: Bool = false,
                allowConsonantZFWJ: Bool = false,
                upperCaseFirstChar: Bool = false,
                useMacro: Bool = false,
                autoCapsMacro: Bool = false) {
        self.inputType = inputType
        self.modernOrthography = modernOrthography
        self.checkSpelling = checkSpelling
        self.restoreIfWrong = restoreIfWrong
        self.freeMark = freeMark
        self.quickTelex = quickTelex
        self.quickStartConsonant = quickStartConsonant
        self.quickEndConsonant = quickEndConsonant
        self.allowConsonantZFWJ = allowConsonantZFWJ
        self.upperCaseFirstChar = upperCaseFirstChar
        self.useMacro = useMacro
        self.autoCapsMacro = autoCapsMacro
    }
}

/// A character emitted by the engine.
public struct OutputCharacter: Equatable, Sendable {
    /// UTF-16 unit; 0 for a control key (Tab, Enter, arrows...)
    public var unit: UInt16
    /// Non-nil when the character is a plain, untransformed key. These can be sent by key code (with Shift)
    /// when sending key by key; accented characters are always sent as Unicode.
    public var keyCode: UInt16?
    public var shifted: Bool

    public init(unit: UInt16, keyCode: UInt16? = nil, shifted: Bool = false) {
        self.unit = unit
        self.keyCode = keyCode
        self.shifted = shifted
    }
}

/// Result of handling one key: "delete `backspaces` characters, then type `characters` (+ `restoreKey`)".
///
/// Reusable across keys (`reset()` keeps its storage) so the key path doesn't allocate.
public struct EngineOutput: Equatable, Sendable {
    public enum Action: Equatable, Sendable {
        /// Do nothing; let the original key through
        case pass
        /// Delete `backspaces` characters and type the output; swallow the original key
        case replace
        /// Macro: delete `backspaces` characters, type `characters`, then resend the key just pressed
        /// (`restoreKey`, with Shift if Shift is held)
        case macro
    }

    public var action: Action = .pass
    /// Raw count from the engine; the key sender only acts on `0 < n < 32`.
    public var backspaces: Int = 0
    /// Characters to type, in display order
    public var characters: [OutputCharacter] = []
    /// For a restored (invalid) word or a macro: the key just pressed, sent after `characters`
    public var restoreKey: OutputCharacter?
    /// Engine asks not to insert the empty character used to defeat autocomplete
    public var noEmptyCharPrefix: Bool = false

    public init() {
        characters.reserveCapacity(64)
    }

    public init(action: Action, backspaces: Int = 0, characters: [OutputCharacter] = [],
                restoreKey: OutputCharacter? = nil, noEmptyCharPrefix: Bool = false) {
        self.action = action
        self.backspaces = backspaces
        self.characters = characters
        self.restoreKey = restoreKey
        self.noEmptyCharPrefix = noEmptyCharPrefix
    }

    /// The original key must be resent (the restore key is a control key)
    public var resendKey: Bool {
        if action == .macro { return false }
        if let restoreKey { return restoreKey.unit == 0 }
        return false
    }

    /// Resulting text, including the restore key. Allocates; for tests and logging only.
    public var text: [UInt16] {
        var units = characters.map(\.unit).filter { $0 != 0 }
        if let restoreKey, restoreKey.unit != 0 { units.append(restoreKey.unit) }
        return units
    }

    public mutating func reset() {
        action = .pass
        backspaces = 0
        characters.removeAll(keepingCapacity: true)
        restoreKey = nil
        noEmptyCharPrefix = false
    }
}

/// Vietnamese typing state machine. Input is macOS key codes (kVK_*), output is `EngineOutput`.
///
/// Implemented by `VietnameseEngine`. `LiteKeyCore` depends only on this protocol, so it can be tested
/// with a fake engine.
public protocol TypingEngine {
    mutating func configure(_ config: EngineConfig)
    /// Start a new word (mouse click, app switch, mode change...)
    mutating func newSession()
    /// Handle one keyDown. `otherModifier`: ⌘/⌃/⌥/Fn is held.
    mutating func handleKey(code: UInt16, caps: CapsState, otherModifier: Bool, into output: inout EngineOutput)
    /// Toggle spell checking off/on for the current word
    mutating func tempOffSpellChecking()
    /// Turn the engine off until the end of the current word
    mutating func tempOffEngine()
    mutating func setMacros(_ table: MacroTable)
    /// Handle a key while Vietnamese typing is off but macros stay enabled: only tracks macros
    mutating func handleEnglishModeKey(code: UInt16, caps: CapsState, otherModifier: Bool, into output: inout EngineOutput)
}
