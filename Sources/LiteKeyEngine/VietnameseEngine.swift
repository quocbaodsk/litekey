// Swift port of the OpenKey input engine (github.com/tuyenvm/OpenKey), © Mai Vũ Tuyên, GPL-3.0.
//
// A few quirks are kept so the output matches Tests/fixtures exactly: loop counters shared across
// functions (i, j, k, ii, iii, kk, l) are struct properties because some functions read values others leave
// behind; byte-sized state is stored as `UInt8` and truncates on assignment; out-of-bounds reads return 0
// and out-of-bounds writes are ignored.

/// Bit masks used in engine character codes.
enum EngineMasks {
    static let caps: UInt32 = 0x10000
    static let tone: UInt32 = 0x20000
    static let toneW: UInt32 = 0x40000
    static let mark1: UInt32 = 0x80000
    static let mark2: UInt32 = 0x100000
    static let mark3: UInt32 = 0x200000
    static let mark4: UInt32 = 0x400000
    static let mark5: UInt32 = 0x800000
    static let mark: UInt32 = 0xF80000
    static let char: UInt32 = 0xFFFF
    static let standalone: UInt32 = 0x1000000
    static let charCode: UInt32 = 0x2000000
    static let pureCharacter: UInt32 = 0x80000000
    static let endConsonant: UInt32 = 0x4000
    static let consonantAllow: UInt32 = 0x8000
}

/// macOS virtual key codes (kVK_*) used by the engine.
enum EngineKey {
    static let esc: UInt32 = 53, delete: UInt32 = 51, tab: UInt32 = 48, enter: UInt32 = 76, returnKey: UInt32 = 36
    static let space: UInt32 = 49, left: UInt32 = 123, right: UInt32 = 124, down: UInt32 = 125, up: UInt32 = 126
    static let a: UInt32 = 0, b: UInt32 = 11, c: UInt32 = 8, d: UInt32 = 2, e: UInt32 = 14, f: UInt32 = 3
    static let g: UInt32 = 5, h: UInt32 = 4, i: UInt32 = 34, j: UInt32 = 38, k: UInt32 = 40, l: UInt32 = 37
    static let m: UInt32 = 46, n: UInt32 = 45, o: UInt32 = 31, p: UInt32 = 35, q: UInt32 = 12, r: UInt32 = 15
    static let s: UInt32 = 1, t: UInt32 = 17, u: UInt32 = 32, v: UInt32 = 9, w: UInt32 = 13, x: UInt32 = 7
    static let y: UInt32 = 16, z: UInt32 = 6
    static let k1: UInt32 = 18, k2: UInt32 = 19, k3: UInt32 = 20, k4: UInt32 = 21, k5: UInt32 = 23
    static let k6: UInt32 = 22, k7: UInt32 = 26, k8: UInt32 = 28, k9: UInt32 = 25, k0: UInt32 = 29
    static let leftBracket: UInt32 = 33, rightBracket: UInt32 = 30
    static let dot: UInt32 = 47, backquote: UInt32 = 50, minus: UInt32 = 27, equals: UInt32 = 24
    static let backSlash: UInt32 = 42, semicolon: UInt32 = 41, quote: UInt32 = 39, comma: UInt32 = 43, slash: UInt32 = 44
}

/// Result code the engine leaves in `hCode` after handling a key.
enum HookCode {
    static let doNothing = 0
    static let willProcess = 1
    static let breakWord = 2
    static let restore = 3
    static let replaceMacro = 4
    static let restoreAndStartNewSession = 5
}

/// Vietnamese typing engine (Telex, VNI, Simple Telex).
public struct VietnameseEngine: TypingEngine {
    static let maxBuff = 32
    private typealias K = EngineKey
    private typealias M = EngineMasks

    static let charKeyCode: [UInt32] = [
        K.backquote, K.k1, K.k2, K.k3, K.k4, K.k5, K.k6, K.k7, K.k8, K.k9, K.k0, K.minus, K.equals,
        K.leftBracket, K.rightBracket, K.backSlash,
        K.semicolon, K.quote, K.comma, K.dot, K.slash,
    ]
    static let breakCode: [UInt32] = [
        K.esc, K.tab, K.enter, K.returnKey, K.left, K.right, K.down, K.up, K.comma, K.dot,
        K.slash, K.semicolon, K.quote, K.backSlash, K.minus, K.equals, K.backquote, K.tab,
    ]
    static let macroBreakCode: [UInt32] = [
        K.returnKey, K.comma, K.dot, K.slash, K.semicolon, K.quote, K.backSlash, K.minus, K.equals,
    ]
    /// Processing keys per input type: Telex, VNI, Simple Telex 1, Simple Telex 2
    static let processingChar: [[UInt32]] = [
        [K.s, K.f, K.r, K.x, K.j, K.a, K.o, K.e, K.w, K.d, K.z],
        [K.k1, K.k2, K.k3, K.k4, K.k5, K.k6, K.k6, K.k7, K.k8, K.k9, K.k0],
        [K.s, K.f, K.r, K.x, K.j, K.a, K.o, K.e, K.w, K.d, K.z],
        [K.s, K.f, K.r, K.x, K.j, K.a, K.o, K.e, K.w, K.d, K.z],
    ]

    // MARK: - Configuration

    var vInputType = 0
    var vFreeMark = 0
    var vCheckSpelling = 1
    var vUseModernOrthography = 0
    var vQuickTelex = 0
    var vRestoreIfWrongSpelling = 1
    var vUseMacro = 0
    var vUpperCaseFirstChar = 0
    var vAllowConsonantZFWJ = 0
    var vQuickStartConsonant = 0
    var vQuickEndConsonant = 0
    var vAutoCapsMacro = 0
    /// Macro (text expansion) table
    var macroTable = MacroTable()

    // MARK: - Hook state (result handed to the key sender)

    private var hCode8: UInt8 = 0
    private var hBPC8: UInt8 = 0
    private var hNCC8: UInt8 = 0
    private var hExt8: UInt8 = 0
    var hCode: Int { get { Int(hCode8) } set { hCode8 = UInt8(truncatingIfNeeded: newValue) } }
    var hBPC: Int { get { Int(hBPC8) } set { hBPC8 = UInt8(truncatingIfNeeded: newValue) } }
    var hNCC: Int { get { Int(hNCC8) } set { hNCC8 = UInt8(truncatingIfNeeded: newValue) } }
    var hExt: Int { get { Int(hExt8) } set { hExt8 = UInt8(truncatingIfNeeded: newValue) } }
    var hData = [UInt32](repeating: 0, count: maxBuff)
    var hMacroKey: [UInt32] = []
    var hMacroData: [UInt32] = []

    // MARK: - Internal state

    var TypingWord = [UInt32](repeating: 0, count: maxBuff)
    private var index8: UInt8 = 0
    var _index: Int { get { Int(index8) } set { index8 = UInt8(truncatingIfNeeded: newValue) } }
    var _longWordHelper: [UInt32] = []
    var _typingStates = TypingHistory(entries: maxTypingStates, elementsPerEntry: maxBuff)
    var _typingStatesData: [UInt32] = []

    var KeyStates = [UInt32](repeating: 0, count: maxBuff)
    private var stateIndex8: UInt8 = 0
    var _stateIndex: Int { get { Int(stateIndex8) } set { stateIndex8 = UInt8(truncatingIfNeeded: newValue) } }

    var tempDisableKey = false
    var capsElem = 0
    var key: UInt32 = 0
    var markElem = 0
    var isCorect = false
    var isChanged = false
    private var vowelCount8: UInt8 = 0
    private var vsi8: UInt8 = 0
    private var vei8: UInt8 = 0
    private var vwsm8: UInt8 = 0
    var vowelCount: Int { get { Int(vowelCount8) } set { vowelCount8 = UInt8(truncatingIfNeeded: newValue) } }
    var VSI: Int { get { Int(vsi8) } set { vsi8 = UInt8(truncatingIfNeeded: newValue) } }
    var VEI: Int { get { Int(vei8) } set { vei8 = UInt8(truncatingIfNeeded: newValue) } }
    var VWSM: Int { get { Int(vwsm8) } set { vwsm8 = UInt8(truncatingIfNeeded: newValue) } }
    var i = 0, ii = 0, iii = 0
    var j = 0
    var k = 0, kk = 0
    var l = 0
    var isRestoredW = false
    /// The current word was restored by backspacing over a space into the previous word, but `KeyStates`
    /// no longer holds its keystrokes (another word was started since). See `checkRestoreIfWrongSpelling`.
    var _keyStatesIncomplete = false
    var keyForAEO: UInt32 = 0
    var isCheckedGrammar = false
    var _isCaps = false
    var _spaceCount = 0
    var _hasHandledMacro = false
    private var upperCaseStatus8: UInt8 = 0
    var _upperCaseStatus: Int { get { Int(upperCaseStatus8) } set { upperCaseStatus8 = UInt8(truncatingIfNeeded: newValue) } }
    var _isCharKeyCode = false
    var _specialChar: [UInt32] = []
    var _useSpellCheckingBefore = false
    var _hasHandleQuickConsonant = false
    var _willTempOffEngine = false

    var _spellingOK = false
    var _spellingFlag = false
    var _spellingVowelOK = false
    private var spellingEndIndex8: UInt8 = 0
    var _spellingEndIndex: Int { get { Int(spellingEndIndex8) } set { spellingEndIndex8 = UInt8(truncatingIfNeeded: newValue) } }

    // MARK: - API

    public init(config: EngineConfig = EngineConfig()) {
        Self.warmUpTables()
        // Reserve once here; the key handlers clear these with keepingCapacity so typing doesn't allocate
        hMacroKey.reserveCapacity(Self.maxBuff)
        _longWordHelper.reserveCapacity(Self.maxBuff)
        _typingStatesData.reserveCapacity(Self.maxBuff)
        _specialChar.reserveCapacity(Self.maxBuff)
        vKeyInit()
        configure(config)
    }

    /// `static let` lookup tables are built lazily on first use, which would be inside the first key's
    /// callback (a few dozen Dictionary allocations). Build them up front instead.
    private static func warmUpTables() {
        _ = VietnameseData.vowelByKey.count
        _ = VietnameseData.vowelCombineByKey.count
        _ = VietnameseData.quickStartConsonantByKey.count
        _ = VietnameseData.quickEndConsonantByKey.count
        _ = VietnameseData.quickTelexByKey.count
        _ = VietnameseData.unicodeByKey.count
        _ = VietnameseData.keyCodeToChar.count
        _ = VietnameseData.characterKeyCode.count
    }

    public mutating func configure(_ c: EngineConfig) {
        vInputType = c.inputType.rawValue
        vUseModernOrthography = c.modernOrthography ? 1 : 0
        vCheckSpelling = c.checkSpelling ? 1 : 0
        vRestoreIfWrongSpelling = (c.checkSpelling && c.restoreIfWrong) ? 1 : 0
        vFreeMark = c.freeMark ? 1 : 0
        vQuickTelex = c.quickTelex ? 1 : 0
        vQuickStartConsonant = c.quickStartConsonant ? 1 : 0
        vQuickEndConsonant = c.quickEndConsonant ? 1 : 0
        vAllowConsonantZFWJ = c.allowConsonantZFWJ ? 1 : 0
        vUpperCaseFirstChar = c.upperCaseFirstChar ? 1 : 0
        vUseMacro = c.useMacro ? 1 : 0
        vAutoCapsMacro = c.autoCapsMacro ? 1 : 0
        vSetCheckSpelling()
        startNewSession()
    }

    public mutating func newSession() {
        vKeyHandleEvent(isMouse: true, data: 0)
        // With restore-if-wrong-spelling on and a misspelled current word, the mouse event takes the restore
        // branch (`hCode` = restore...), which skips `startNewSession()`. The restore result is never sent
        // (a click or app switch types nothing), so the old word and `tempDisableKey` would linger and the
        // next word would get no marks ("baanfk", click, "as" gives "as"). So start a new word here,
        // as the `doNothing` branch does.
        if hCode != HookCode.doNothing {
            hCode = HookCode.doNothing
            startNewSession()
            vCheckSpelling = _useSpellCheckingBefore ? 1 : 0
            _willTempOffEngine = false
        }
    }

    public mutating func tempOffSpellChecking() {
        vTempOffSpellChecking()
    }

    public mutating func tempOffEngine() {
        vTempOffEngine()
    }

    public mutating func setMacros(_ table: MacroTable) {
        macroTable = table
    }

    /// Handles a key while Vietnamese typing is off; only macros are tracked.
    public mutating func handleEnglishModeKey(code: UInt16, caps: CapsState, otherModifier: Bool, into output: inout EngineOutput) {
        output.reset()
        vEnglishMode(isMouse: false, data: UInt32(code), isCaps: caps != .none, otherControlKey: otherModifier)
        if hCode == HookCode.replaceMacro {
            fillMacro(code: code, caps: caps, into: &output)
        }
    }

    /// Macro expansion: delete `hBPC` characters, type `hMacroData`, then resend the key just pressed.
    private func fillMacro(code: UInt16, caps: CapsState, into output: inout EngineOutput) {
        output.action = .macro
        output.backspaces = hBPC
        for data in hMacroData {
            output.characters.append(Self.outputCharacter(data))
        }
        // Resend the key by key code, with Shift only if Shift is held (Caps Lock does not count)
        output.restoreKey = OutputCharacter(unit: 0, keyCode: code, shifted: caps == .shift)
    }

    /// Handles one keyDown and fills `output` with what to send.
    public mutating func handleKey(code: UInt16, caps: CapsState, otherModifier: Bool, into output: inout EngineOutput) {
        output.reset()
        vKeyHandleEvent(isMouse: false, data: UInt32(code), capsStatus: Int(caps.rawValue), otherControlKey: otherModifier)

        let code32 = UInt32(code)
        let c = hCode
        if c == HookCode.replaceMacro {
            fillMacro(code: code, caps: caps, into: &output)
            return
        }
        guard c == HookCode.willProcess || c == HookCode.restore || c == HookCode.restoreAndStartNewSession else { return }

        output.action = .replace
        output.noEmptyCharPrefix = hExt == 4
        output.backspaces = hBPC

        // hData is stored in reverse order
        let count = hNCC <= Self.maxBuff ? hNCC : 0
        var n = count - 1
        while n >= 0 {
            output.characters.append(Self.outputCharacter(hData[n]))
            n -= 1
        }

        if c == HookCode.restore || c == HookCode.restoreAndStartNewSession {
            let capsMask: UInt32 = caps != .none ? M.caps : 0
            output.restoreKey = OutputCharacter(unit: VietnameseData.character(for: code32 | capsMask),
                                                keyCode: code, shifted: caps != .none)
            if c == HookCode.restoreAndStartNewSession {
                startNewSession()
            }
        }
    }

    /// Converts an engine character code to an output character (Unicode only).
    static func outputCharacter(_ c: UInt32) -> OutputCharacter {
        if c & M.pureCharacter != 0 {
            return OutputCharacter(unit: UInt16(truncatingIfNeeded: c))
        } else if c & M.charCode == 0 {
            return OutputCharacter(unit: VietnameseData.character(for: c),
                                   keyCode: UInt16(truncatingIfNeeded: c),
                                   shifted: c & M.caps != 0)
        }
        return OutputCharacter(unit: UInt16(truncatingIfNeeded: c))
    }

    // MARK: - Bounds-checked buffer access

    /// Key code at `index` in the current word, without masks.
    @inline(__always) private func CHR(_ index: Int) -> UInt32 {
        guard index >= 0 && index < Self.maxBuff else { return 0 }
        return TypingWord[index] & 0xFFFF
    }

    @inline(__always) private func TW(_ index: Int) -> UInt32 {
        guard index >= 0 && index < Self.maxBuff else { return 0 }
        return TypingWord[index]
    }

    @inline(__always) private mutating func setTW(_ index: Int, _ value: UInt32) {
        guard index >= 0 && index < Self.maxBuff else { return }
        TypingWord[index] = value
    }

    @inline(__always) private mutating func setHData(_ index: Int, _ value: UInt32) {
        guard index >= 0 && index < Self.maxBuff else { return }
        hData[index] = value
    }

    // MARK: - Key classification helpers

    private func IS_CONSONANT(_ keyCode: UInt32) -> Bool {
        !(keyCode == K.a || keyCode == K.e || keyCode == K.u || keyCode == K.y || keyCode == K.i || keyCode == K.o)
    }

    private func pc(_ n: Int) -> UInt32 { Self.processingChar[vInputType][n] }
    private func IS_KEY_Z(_ key: UInt32) -> Bool { pc(10) == key }
    private func IS_KEY_D(_ key: UInt32) -> Bool { pc(9) == key }
    private func IS_KEY_W(_ key: UInt32) -> Bool {
        vInputType != 1 ? pc(8) == key : (pc(8) == key || pc(7) == key)
    }
    private func IS_KEY_DOUBLE(_ key: UInt32) -> Bool {
        vInputType != 1 ? (pc(5) == key || pc(6) == key || pc(7) == key) : pc(6) == key
    }
    private func IS_KEY_S(_ key: UInt32) -> Bool { pc(0) == key }
    private func IS_KEY_F(_ key: UInt32) -> Bool { pc(1) == key }
    private func IS_KEY_R(_ key: UInt32) -> Bool { pc(2) == key }
    private func IS_KEY_X(_ key: UInt32) -> Bool { pc(3) == key }
    private func IS_KEY_J(_ key: UInt32) -> Bool { pc(4) == key }

    private func IS_MARK_KEY(_ keyCode: UInt32) -> Bool {
        (vInputType != 1 && (keyCode == K.s || keyCode == K.f || keyCode == K.r || keyCode == K.j || keyCode == K.x)) ||
            (vInputType == 1 && (keyCode == K.k1 || keyCode == K.k2 || keyCode == K.k3 || keyCode == K.k5 || keyCode == K.k4))
    }

    private func IS_BRACKET_KEY(_ key: UInt32) -> Bool {
        key == K.leftBracket || key == K.rightBracket
    }

    private func IS_SPECIALKEY(_ keyCode: UInt32) -> Bool {
        switch vInputType {
        case 0:
            return keyCode == K.w || keyCode == K.e || keyCode == K.r || keyCode == K.o || keyCode == K.leftBracket ||
                keyCode == K.rightBracket || keyCode == K.a || keyCode == K.s || keyCode == K.d || keyCode == K.f ||
                keyCode == K.j || keyCode == K.z || keyCode == K.x || keyCode == K.w
        case 1:
            return keyCode == K.k1 || keyCode == K.k2 || keyCode == K.k3 || keyCode == K.k4 || keyCode == K.k5 ||
                keyCode == K.k6 || keyCode == K.k7 || keyCode == K.k8 || keyCode == K.k9 || keyCode == K.k0
        case 2, 3:
            return keyCode == K.w || keyCode == K.e || keyCode == K.r || keyCode == K.o || keyCode == K.a ||
                keyCode == K.s || keyCode == K.d || keyCode == K.f || keyCode == K.j || keyCode == K.z ||
                keyCode == K.x || keyCode == K.w
        default:
            return false
        }
    }

    private func IS_QUICK_TELEX_KEY(_ code: UInt32) -> Bool {
        _index > 0 && (code == K.c || code == K.g || code == K.k || code == K.n || code == K.q || code == K.p || code == K.t) &&
            CHR(_index - 1) == code
    }

    private func IS_NUMBER_KEY(_ code: UInt32) -> Bool {
        code == K.k1 || code == K.k2 || code == K.k3 || code == K.k4 || code == K.k5 ||
            code == K.k6 || code == K.k7 || code == K.k8 || code == K.k9 || code == K.k0
    }

    // MARK: - Core engine

    mutating func vKeyInit() {
        _index = 0
        _stateIndex = 0
        _useSpellCheckingBefore = vCheckSpelling != 0
        _typingStatesData.removeAll(keepingCapacity: true)
        _typingStates.removeAll()
        _longWordHelper.removeAll(keepingCapacity: true)
    }

    private mutating func isWordBreak(isMouse: Bool, data: UInt32) -> Bool {
        if isMouse { return true }
        i = 0
        while i < Self.breakCode.count {
            if Self.breakCode[i] == data { return true }
            i += 1
        }
        return false
    }

    private mutating func isMacroBreakCode(_ data: UInt32) -> Bool {
        i = 0
        while i < Self.macroBreakCode.count {
            if Self.macroBreakCode[i] == data { return true }
            i += 1
        }
        return false
    }

    private mutating func setKeyData(_ index: Int, _ keyCode: UInt32, _ isCaps: Bool) {
        if index < 0 || index >= Self.maxBuff { return }
        TypingWord[index] = keyCode | (isCaps ? M.caps : 0)
    }

    mutating func checkSpelling(_ forceCheckVowel: Bool = false) {
        _spellingOK = false
        _spellingVowelOK = true
        _spellingEndIndex = _index

        if _index > 0 && CHR(_index - 1) == K.rightBracket {
            _spellingEndIndex = _index - 1
        }

        if _spellingEndIndex > 0 {
            j = 0
            // Check first consonant
            if IS_CONSONANT(CHR(0)) {
                let table = VietnameseData.consonantTable
                i = 0
                while i < table.count {
                    _spellingFlag = false
                    if _spellingEndIndex < table[i].count {
                        _spellingFlag = true
                    }
                    j = 0
                    while j < table[i].count {
                        if _spellingEndIndex > j &&
                            (table[i][j] & ~(vQuickStartConsonant != 0 ? M.endConsonant : 0)) != CHR(j) &&
                            (table[i][j] & ~(vAllowConsonantZFWJ != 0 ? M.consonantAllow : 0)) != CHR(j) {
                            _spellingFlag = true
                            break
                        }
                        j += 1
                    }
                    if _spellingFlag {
                        i += 1
                        continue
                    }
                    break
                }
            }

            if j == _spellingEndIndex { // for "d" case
                _spellingOK = true
            }

            // check next vowel
            k = j
            VSI = k
            // handle "que't"
            if CHR(VSI) == K.u && k > 0 && k < _spellingEndIndex - 1 && CHR(VSI - 1) == K.q {
                k = k + 1
                j = k
                VSI = k
            } else if _index >= 2 && CHR(0) == K.g && CHR(1) == K.i && IS_CONSONANT(CHR(2)) {
                k = 1; j = 1; VSI = 1 // handle "gìn"
            }
            l = 0
            while l < 3 {
                if k < _spellingEndIndex && !IS_CONSONANT(CHR(k)) {
                    k += 1
                    VEI = k
                }
                l += 1
            }
            if k > j { // has vowel
                _spellingVowelOK = false
                // check correct combined vowel
                if k - j > 1 && forceCheckVowel {
                    let vowelSet = VietnameseData.vowelCombineByKey[CHR(j)] ?? []
                    l = 0
                    while l < vowelSet.count {
                        _spellingFlag = false
                        ii = 1
                        while ii < vowelSet[l].count {
                            if j + ii - 1 < _spellingEndIndex &&
                                vowelSet[l][ii] != (CHR(j + ii - 1) | (TW(j + ii - 1) & M.toneW) | (TW(j + ii - 1) & M.tone)) {
                                _spellingFlag = true
                                break
                            }
                            ii += 1
                        }
                        if _spellingFlag || (k < _spellingEndIndex && vowelSet[l][0] == 0) ||
                            (j + ii - 1 < _spellingEndIndex && !IS_CONSONANT(CHR(j + ii - 1))) {
                            l += 1
                            continue
                        }
                        _spellingVowelOK = true
                        break
                    }
                } else if !IS_CONSONANT(CHR(j)) {
                    _spellingVowelOK = true
                }

                // continue check last consonant
                let endTable = VietnameseData.endConsonantTable
                ii = 0
                while ii < endTable.count {
                    _spellingFlag = false
                    j = 0
                    while j < endTable[ii].count {
                        if _spellingEndIndex > k + j &&
                            (endTable[ii][j] & ~(vQuickEndConsonant != 0 ? M.endConsonant : 0)) != CHR(k + j) {
                            _spellingFlag = true
                            break
                        }
                        j += 1
                    }
                    if _spellingFlag {
                        ii += 1
                        continue
                    }
                    if k + j >= _spellingEndIndex {
                        _spellingOK = true
                        break
                    }
                    ii += 1
                }

                // limit: end consonant "ch", "t" can not use with "~", "`", "?"
                if _spellingOK {
                    if _index >= 3 && CHR(_index - 1) == K.h && CHR(_index - 2) == K.c &&
                        !((TW(_index - 3) & M.mark1) != 0 || (TW(_index - 3) & M.mark5) != 0 || (TW(_index - 3) & M.mark) == 0) {
                        _spellingOK = false
                    } else if _index >= 2 && CHR(_index - 1) == K.t &&
                        !((TW(_index - 2) & M.mark1) != 0 || (TW(_index - 2) & M.mark5) != 0 || (TW(_index - 2) & M.mark) == 0) {
                        _spellingOK = false
                    }
                }
            }
        } else {
            _spellingOK = true
        }
        tempDisableKey = !(_spellingOK && _spellingVowelOK)
    }

    private mutating func checkGrammar(_ deltaBackSpace: Int) {
        if _index <= 1 || _index >= Self.maxBuff { return }

        findAndCalculateVowel(true)
        if vowelCount == 0 { return }

        isCheckedGrammar = false

        l = VSI

        // if N key for case: "thuơn", "ưoi", "ưom", "ưoc"
        if _index >= 3 {
            i = _index - 1
            while i >= 0 {
                if CHR(i) == K.n || CHR(i) == K.c || CHR(i) == K.i ||
                    CHR(i) == K.m || CHR(i) == K.p || CHR(i) == K.t {
                    if i - 2 >= 0 && CHR(i - 1) == K.o && CHR(i - 2) == K.u {
                        if ((TW(i - 1) & M.toneW) ^ (TW(i - 2) & M.toneW)) != 0 {
                            setTW(i - 2, TW(i - 2) | M.toneW)
                            setTW(i - 1, TW(i - 1) | M.toneW)
                            isCheckedGrammar = true
                            break
                        }
                    }
                }
                i -= 1
            }
        }

        // check mark
        if _index >= 2 {
            i = l
            while i <= VEI {
                if TW(i) & M.mark != 0 {
                    let mark = TW(i) & M.mark
                    setTW(i, TW(i) & ~M.mark)
                    insertMark(mark, false)
                    if i != VWSM {
                        isCheckedGrammar = true
                    }
                    break
                }
                i += 1
            }
        }

        // re-arrange data to sendback
        if isCheckedGrammar {
            if hCode == HookCode.doNothing {
                hCode = HookCode.willProcess
            }
            hBPC = 0

            i = _index - 1
            while i >= l {
                hBPC += 1
                setHData(_index - 1 - i, getCharacterCode(TW(i)))
                i -= 1
            }
            hNCC = hBPC
            hBPC += deltaBackSpace
            hExt = 4
        }
    }

    private mutating func insertKey(_ keyCode: UInt32, _ isCaps: Bool, _ isCheckSpelling: Bool = true) {
        if _index >= Self.maxBuff {
            _longWordHelper.append(TypingWord[0]) // save long word
            // left shift
            iii = 0
            while iii < Self.maxBuff - 1 {
                TypingWord[iii] = TypingWord[iii + 1]
                iii += 1
            }
            setKeyData(_index - 1, keyCode, isCaps)
        } else {
            setKeyData(_index, keyCode, isCaps)
            _index += 1
        }

        if vCheckSpelling != 0 && isCheckSpelling {
            checkSpelling()
        }

        // allow d after consonant
        if keyCode == K.d && _index - 2 >= 0 && IS_CONSONANT(CHR(_index - 2)) {
            tempDisableKey = false
        }
    }

    private mutating func insertState(_ keyCode: UInt32, _ isCaps: Bool) {
        if _stateIndex >= Self.maxBuff {
            // left shift
            iii = 0
            while iii < Self.maxBuff - 1 {
                KeyStates[iii] = KeyStates[iii + 1]
                iii += 1
            }
            if _stateIndex - 1 < Self.maxBuff {
                KeyStates[_stateIndex - 1] = keyCode | (isCaps ? M.caps : 0)
            }
        } else {
            KeyStates[_stateIndex] = keyCode | (isCaps ? M.caps : 0)
            _stateIndex += 1
        }
    }

    /// Word history used to backspace into the previous word. It is only cleared on Enter, Tab, arrows,
    /// clicks..., so hours of typing without a line break would grow it forever (one entry per space) and
    /// occasionally reallocate it inside the callback. Keep the most recent `maxTypingStates` entries;
    /// beyond that the engine treats the position as the start of a line.
    static let maxTypingStates = 128

    private mutating func pushTypingState() {
        _typingStates.append(_typingStatesData)
        if _typingStates.count > Self.maxTypingStates {
            _typingStates.removeFirst(Self.maxTypingStates / 2)
        }
    }

    private mutating func saveWord() {
        // save word history
        if hCode != HookCode.replaceMacro {
            if _index > 0 {
                if _longWordHelper.count > 0 { // save long word first
                    _typingStatesData.removeAll(keepingCapacity: true)
                    i = 0
                    while i < _longWordHelper.count {
                        if i != 0 && i % Self.maxBuff == 0 { // save if overflow
                            pushTypingState()
                            _typingStatesData.removeAll(keepingCapacity: true)
                        }
                        _typingStatesData.append(_longWordHelper[i])
                        i += 1
                    }
                    pushTypingState()
                    _longWordHelper.removeAll(keepingCapacity: true)
                }

                // save current word
                _typingStatesData.removeAll(keepingCapacity: true)
                i = 0
                while i < _index {
                    _typingStatesData.append(TW(i))
                    i += 1
                }
                pushTypingState()
            }
        } else { // save macro words
            _typingStatesData.removeAll(keepingCapacity: true)
            i = 0
            while i < hMacroData.count {
                if i != 0 && i % Self.maxBuff == 0 { // break if overflow
                    pushTypingState()
                    _typingStatesData.removeAll(keepingCapacity: true)
                }
                _typingStatesData.append(hMacroData[i])
                i += 1
            }
            pushTypingState()
        }
    }

    private mutating func saveWord(_ keyCode: UInt32, _ count: Int) {
        _typingStatesData.removeAll(keepingCapacity: true)
        i = 0
        while i < count {
            _typingStatesData.append(keyCode)
            i += 1
        }
        pushTypingState()
    }

    private mutating func saveSpecialChar() {
        _typingStatesData.removeAll(keepingCapacity: true)
        i = 0
        while i < _specialChar.count {
            _typingStatesData.append(_specialChar[i])
            i += 1
        }
        pushTypingState()
        _specialChar.removeAll(keepingCapacity: true)
    }

    private mutating func restoreLastTypingState() {
        if _typingStates.count > 0 {
            _typingStates.removeLast(into: &_typingStatesData)
            if _typingStatesData.count > 0 {
                if _typingStatesData[0] == K.space {
                    _spaceCount = _typingStatesData.count
                    _index = 0
                } else if Self.charKeyCode.contains(_typingStatesData[0] & 0xFFFF) {
                    _index = 0
                    // Copy instead of assigning: a shared buffer would be copied on the next append
                    _specialChar.removeAll(keepingCapacity: true)
                    _specialChar.append(contentsOf: _typingStatesData)
                    checkSpelling()
                } else {
                    i = 0
                    while i < _typingStatesData.count {
                        setTW(i, _typingStatesData[i])
                        i += 1
                    }
                    _index = _typingStatesData.count
                    if _stateIndex < _index { _keyStatesIncomplete = true }
                }
            }
        }
    }

    mutating func startNewSession() {
        _index = 0
        hBPC = 0
        hNCC = 0
        tempDisableKey = false
        _stateIndex = 0
        _hasHandledMacro = false
        _hasHandleQuickConsonant = false
        _longWordHelper.removeAll(keepingCapacity: true)
        _keyStatesIncomplete = false
    }

    /// Checks whether the word ends with `charset[self[keyPath: iRef]]` and clears `isCorect` if not.
    /// The row index is read through a shared counter, and the shared counters `j` and `k` are overwritten.
    private mutating func checkCorrectVowel(_ charset: [[UInt32]], _ iRef: WritableKeyPath<VietnameseEngine, Int>,
                                            _ markKey: UInt32) {
        // ignore "qu" case
        if _index >= 2 && CHR(_index - 1) == K.u && CHR(_index - 2) == K.q {
            isCorect = false
            return
        }
        let idx = self[keyPath: iRef]
        k = _index - 1
        j = charset[idx].count - 1
        while j >= 0 {
            if (charset[idx][j] & ~(vQuickEndConsonant != 0 ? M.endConsonant : 0)) != CHR(k) {
                isCorect = false
                return
            }
            k -= 1
            if k < 0 { break }
            j -= 1
        }

        // limit mark for end consonant: "C", "T"
        if isCorect && charset[idx].count > 1 && (IS_KEY_F(markKey) || IS_KEY_X(markKey) || IS_KEY_R(markKey)) {
            if charset[idx][1] == K.c || charset[idx][1] == K.t {
                isCorect = false
            } else if charset[idx].count > 2 && charset[idx][2] == K.t {
                isCorect = false
            }
        }

        if isCorect && k >= 0 {
            if CHR(k) == CHR(k + 1) {
                isCorect = false
            }
        }
    }

    /// Converts a key code (with mark/tone flags) to the engine's character code.
    mutating func getCharacterCode(_ data: UInt32) -> UInt32 {
        capsElem = (data & M.caps) != 0 ? 0 : 1
        key = data & M.char
        if data & M.mark != 0 { // has mark
            markElem = -2
            switch data & M.mark {
            case M.mark1: markElem = 0
            case M.mark2: markElem = 2
            case M.mark3: markElem = 4
            case M.mark4: markElem = 6
            case M.mark5: markElem = 8
            default: break
            }
            markElem += capsElem

            switch key {
            case K.a, K.o, K.u, K.e:
                if (data & M.tone) == 0 && (data & M.toneW) == 0 {
                    markElem += 4
                }
            default: break
            }

            if data & M.tone != 0 {
                key |= M.tone
            } else if data & M.toneW != 0 {
                key |= M.toneW
            }
            guard let row = VietnameseData.unicodeByKey[key] else { return data } // not found
            return UInt32(Self.element(row, markElem)) | M.charCode
        } else { // has no mark
            guard let row = VietnameseData.unicodeByKey[key] else { return data } // not found

            if data & M.tone != 0 {
                return UInt32(Self.element(row, capsElem)) | M.charCode
            } else if data & M.toneW != 0 {
                return UInt32(Self.element(row, capsElem + 2)) | M.charCode
            } else {
                return data // not found
            }
        }
    }

    private static func element(_ row: [UInt16], _ index: Int) -> UInt16 {
        index >= 0 && index < row.count ? row[index] : 0
    }

    private mutating func findAndCalculateVowel(_ forGrammar: Bool = false) {
        vowelCount = 0
        VSI = 0
        VEI = 0
        iii = _index - 1
        while iii >= 0 {
            if IS_CONSONANT(CHR(iii)) {
                if vowelCount > 0 { break }
            } else { // is vowel
                if vowelCount == 0 {
                    VEI = iii
                }
                if !forGrammar {
                    if (iii - 1 >= 0 && (CHR(iii) == K.i && CHR(iii - 1) == K.g)) ||
                        (iii - 1 >= 0 && (CHR(iii) == K.u && CHR(iii - 1) == K.q)) {
                        break
                    }
                }
                VSI = iii
                vowelCount += 1
            }
            iii -= 1
        }
        // don't count the "u" in "qu" as a vowel
        if VSI - 1 >= 0 && CHR(VSI) == K.u && CHR(VSI - 1) == K.q {
            VSI += 1
            vowelCount -= 1
        }
    }

    private mutating func removeMark() {
        findAndCalculateVowel(true)
        isChanged = false
        if _index > 0 {
            i = VSI
            while i <= VEI {
                if TW(i) & M.mark != 0 {
                    setTW(i, TW(i) & ~M.mark)
                    isChanged = true
                }
                i += 1
            }
        }
        if isChanged {
            hCode = HookCode.willProcess
            hBPC = 0

            i = _index - 1
            while i >= VSI {
                hBPC += 1
                setHData(_index - 1 - i, getCharacterCode(TW(i)))
                i -= 1
            }
            hNCC = hBPC
        } else {
            hCode = HookCode.doNothing
        }
    }

    private mutating func canHasEndConsonant() -> Bool {
        let vo = VietnameseData.vowelCombineByKey[CHR(VSI)] ?? []
        ii = 0
        while ii < vo.count {
            kk = VSI
            iii = 1
            while iii < vo[ii].count {
                if kk > VEI || ((CHR(kk) | (TW(kk) & M.tone) | (TW(kk) & M.toneW)) != vo[ii][iii]) {
                    break
                }
                kk += 1
                iii += 1
            }
            if iii >= vo[ii].count {
                return vo[ii][0] == 1
            }
            ii += 1
        }
        return false
    }

    private mutating func handleModernMark() {
        // default
        VWSM = VEI
        hBPC = _index - VEI

        // rule 2
        if vowelCount == 3 && ((CHR(VSI) == K.o && CHR(VSI + 1) == K.a && CHR(VSI + 2) == K.i) ||
                                (CHR(VSI) == K.u && CHR(VSI + 1) == K.y && CHR(VSI + 2) == K.u) ||
                                (CHR(VSI) == K.o && CHR(VSI + 1) == K.e && CHR(VSI + 2) == K.o) ||
                                (CHR(VSI) == K.u && CHR(VSI + 1) == K.y && CHR(VSI + 2) == K.a)) {
            VWSM = VSI + 1
            hBPC = _index - VWSM
        } else if (CHR(VSI) == K.o && CHR(VSI + 1) == K.i) ||
                    (CHR(VSI) == K.a && CHR(VSI + 1) == K.i) ||
                    (CHR(VSI) == K.u && CHR(VSI + 1) == K.i) {
            VWSM = VSI
            hBPC = _index - VWSM
        } else if CHR(VEI - 1) == K.a && CHR(VEI) == K.y {
            VWSM = VEI - 1
            hBPC = (_index - VEI) + 1
        } else if CHR(VSI) == K.u && CHR(VSI + 1) == K.o {
            VWSM = VSI + 1
            hBPC = _index - VWSM
        } else if CHR(VSI + 1) == K.o || CHR(VSI + 1) == K.u {
            VWSM = VEI - 1
            hBPC = (_index - VEI) + 1
        } else if CHR(VSI) == K.o || CHR(VSI) == K.u {
            VWSM = VEI
            hBPC = _index - VEI
        }

        // rule 3.1
        if (CHR(VSI) == K.i && (TW(VSI + 1) & (K.e | M.tone)) != 0) ||
            (CHR(VSI) == K.y && (TW(VSI + 1) & (K.e | M.tone)) != 0) ||
            (CHR(VSI) == K.u && (TW(VSI + 1) == (K.o | M.tone))) ||
            ((TW(VSI) == (K.u | M.toneW)) && (TW(VSI + 1) == (K.o | M.toneW))) {
            if VSI + 2 < _index {
                if CHR(VSI + 2) == K.p || CHR(VSI + 2) == K.t ||
                    CHR(VSI + 2) == K.m || CHR(VSI + 2) == K.n ||
                    CHR(VSI + 2) == K.o || CHR(VSI + 2) == K.u ||
                    CHR(VSI + 2) == K.i || CHR(VSI + 2) == K.c ||
                    (VSI + 3 < _index && CHR(VSI + 2) == K.c && CHR(VSI + 2) == K.h) ||
                    (VSI + 3 < _index && CHR(VSI + 2) == K.n && CHR(VSI + 2) == K.h) ||
                    (VSI + 3 < _index && CHR(VSI + 2) == K.n && CHR(VSI + 2) == K.g) {
                    VWSM = VSI + 1
                    hBPC = _index - VWSM
                } else {
                    VWSM = VSI
                    hBPC = _index - VWSM
                }
            } else {
                VWSM = VSI
                hBPC = _index - VWSM
            }
        }
        // rule 3.2
        else if (CHR(VSI) == K.i && (CHR(VSI) == K.a)) ||
                    (CHR(VSI) == K.y && (CHR(VSI) == K.a)) ||
                    (CHR(VSI) == K.u && (CHR(VSI) == K.a)) ||
                    (CHR(VSI) == K.u && (TW(VSI + 1) == (K.u | M.toneW))) {
            VWSM = VSI
            hBPC = _index - VWSM
        }

        // rule 4
        if vowelCount == 2 {
            if ((CHR(VSI) == K.i) && (CHR(VSI + 1) == K.a)) ||
                ((CHR(VSI) == K.i) && (CHR(VSI + 1) == K.u)) ||
                ((CHR(VSI) == K.i) && (CHR(VSI + 1) == K.o)) {
                if VSI == 0 || (CHR(VSI - 1) != K.g) { // no preceding G
                    VWSM = VSI
                    hBPC = _index - VWSM
                } else {
                    VWSM = VSI + 1
                    hBPC = _index - VWSM
                }
            } else if (CHR(VSI) == K.u) && (CHR(VSI + 1) == K.a) {
                if VSI == 0 || (CHR(VSI - 1) != K.q) { // no preceding Q
                    if VEI + 1 >= _index || !canHasEndConsonant() {
                        VWSM = VSI
                        hBPC = _index - VWSM
                    }
                } else {
                    VWSM = VSI + 1
                    hBPC = _index - VWSM
                }
            } else if (CHR(VSI) == K.o) && (CHR(VSI + 1) == K.o) { // thoong
                VWSM = VEI
                hBPC = _index - VWSM
            }
        }
    }

    private mutating func handleOldMark() {
        // default
        if vowelCount == 0 && CHR(VEI) == K.i {
            VWSM = VEI
        } else {
            VWSM = VSI
        }
        hBPC = _index - VWSM

        // rule 2
        if vowelCount == 3 || (VEI + 1 < _index && IS_CONSONANT(CHR(VEI + 1)) && canHasEndConsonant()) {
            VWSM = VSI + 1
            hBPC = _index - VWSM
        }

        // rule 3
        ii = VSI
        while ii <= VEI {
            if (CHR(ii) == K.e && TW(ii) & M.tone != 0) || (CHR(ii) == K.o && TW(ii) & M.toneW != 0) {
                VWSM = ii
                hBPC = _index - VWSM
                break
            }
            ii += 1
        }

        hNCC = hBPC
    }

    private mutating func insertMark(_ markMask: UInt32, _ canModifyFlag: Bool = true) {
        vowelCount = 0

        if canModifyFlag {
            hCode = HookCode.willProcess
        }
        hBPC = 0
        hNCC = 0

        findAndCalculateVowel()
        VWSM = 0

        // detect mark position
        if vowelCount == 1 {
            VWSM = VEI
            hBPC = _index - VEI
        } else { // vowel = 2 or 3
            if vUseModernOrthography == 0 {
                handleOldMark()
            } else {
                handleModernMark()
            }
            if TW(VEI) & M.tone != 0 || TW(VEI) & M.toneW != 0 {
                VWSM = VEI
            }
        }

        // send data
        kk = _index - 1 - VSI
        // if duplicate same mark -> restore
        if TW(VWSM) & markMask != 0 {
            setTW(VWSM, TW(VWSM) & ~M.mark)
            if canModifyFlag {
                hCode = HookCode.restore
            }
            ii = VSI
            while ii < _index {
                setTW(ii, TW(ii) & ~M.mark)
                setHData(kk, getCharacterCode(TW(ii)))
                kk -= 1
                ii += 1
            }
            tempDisableKey = true
        } else {
            // remove other mark
            setTW(VWSM, TW(VWSM) & ~M.mark)

            // add mark
            setTW(VWSM, TW(VWSM) | markMask)
            ii = VSI
            while ii < _index {
                if ii != VWSM { // remove mark for other vowel
                    setTW(ii, TW(ii) & ~M.mark)
                }
                setHData(kk, getCharacterCode(TW(ii)))
                kk -= 1
                ii += 1
            }

            hBPC = _index - VSI
        }
        hNCC = hBPC
    }

    private mutating func insertD(_ data: UInt32, _ isCaps: Bool) {
        hCode = HookCode.willProcess
        hBPC = 0
        ii = _index - 1
        while ii >= 0 {
            hBPC += 1
            if CHR(ii) == K.d { // reverse unicode char
                if TW(ii) & M.tone != 0 {
                    // restore and disable temporary
                    hCode = HookCode.restore
                    setTW(ii, TW(ii) & ~M.tone)
                    setHData(_index - 1 - ii, TW(ii))
                    tempDisableKey = true
                    break
                } else {
                    setTW(ii, TW(ii) | M.tone)
                    setHData(_index - 1 - ii, getCharacterCode(TW(ii)))
                }
                break
            } else { // restore the original char
                setHData(_index - 1 - ii, getCharacterCode(TW(ii)))
            }
            ii -= 1
        }
        hNCC = hBPC
    }

    private mutating func insertAOE(_ data: UInt32, _ isCaps: Bool) {
        findAndCalculateVowel()

        // remove W tone
        var firstUnhorned = _index
        ii = VSI
        while ii <= VEI {
            if TW(ii) & M.toneW != 0 && TW(ii) & M.standalone == 0 && ii < firstUnhorned {
                firstUnhorned = ii
            }
            setTW(ii, TW(ii) & ~M.toneW)
            ii += 1
        }

        hCode = HookCode.willProcess
        hBPC = 0

        ii = _index - 1
        while ii >= 0 {
            hBPC += 1
            if CHR(ii) == data { // reverse unicode char
                if TW(ii) & M.tone != 0 {
                    // restore and disable temporary
                    hCode = HookCode.restore
                    setTW(ii, TW(ii) & ~M.tone)
                    setHData(_index - 1 - ii, TW(ii))
                    if data != K.o { // case thoòng
                        tempDisableKey = true
                    }
                    break
                } else {
                    setTW(ii, TW(ii) | M.tone)
                    if !IS_KEY_D(data) {
                        setTW(ii, TW(ii) & ~M.toneW)
                    }
                    setHData(_index - 1 - ii, getCharacterCode(TW(ii)))
                    // Vowels before the target lost their horn above but the loop stops here, so the screen
                    // kept "ngưôi" while the buffer held "nguôi". Redraw them too.
                    // A standalone ư is left as the fixtures expect (options.tsv "woong" → "ưông").
                    var q = ii - 1
                    while q >= firstUnhorned {
                        hBPC += 1
                        setHData(_index - 1 - q, getCharacterCode(TW(q)))
                        q -= 1
                    }
                }
                break
            } else { // restore the original char
                setHData(_index - 1 - ii, getCharacterCode(TW(ii)))
            }
            ii -= 1
        }
        hNCC = hBPC
    }

    private mutating func insertW(_ data: UInt32, _ isCaps: Bool) {
        isRestoredW = false

        findAndCalculateVowel()

        // remove ^ tone
        ii = VSI
        while ii <= VEI {
            setTW(ii, TW(ii) & ~M.tone)
            ii += 1
        }

        if vowelCount > 1 {
            hBPC = _index - VSI
            hNCC = hBPC

            if ((TW(VSI) & M.toneW) != 0 && (TW(VSI + 1) & M.toneW) != 0) ||
                ((TW(VSI) & M.toneW) != 0 && CHR(VSI + 1) == K.i) ||
                ((TW(VSI) & M.toneW) != 0 && CHR(VSI + 1) == K.a) ||
                // iơ, oă and thuơ carry the horn on the second vowel only; without these a second w
                // was swallowed instead of undoing
                ((TW(VSI + 1) & M.toneW) != 0 && CHR(VSI) == K.i) ||
                ((TW(VSI + 1) & M.toneW) != 0 && CHR(VSI) == K.o && CHR(VSI + 1) == K.a) ||
                ((TW(VSI + 1) & M.toneW) != 0 && CHR(VSI) == K.u && CHR(VSI + 1) == K.o) {
                // restore and disable temporary
                hCode = HookCode.restore

                ii = VSI
                while ii < _index {
                    setTW(ii, TW(ii) & ~M.toneW)
                    setHData(_index - 1 - ii, getCharacterCode(TW(ii)) & ~M.standalone)
                    ii += 1
                }
                isRestoredW = true
                tempDisableKey = true
            } else {
                hCode = HookCode.willProcess

                if CHR(VSI) == K.u && CHR(VSI + 1) == K.o {
                    if VSI - 2 >= 0 && TW(VSI - 2) == K.t && TW(VSI - 1) == K.h {
                        setTW(VSI + 1, TW(VSI + 1) | M.toneW)
                        if VSI + 2 < _index && CHR(VSI + 2) == K.n {
                            setTW(VSI, TW(VSI) | M.toneW)
                        }
                    } else if VSI - 1 >= 0 && TW(VSI - 1) == K.q {
                        setTW(VSI + 1, TW(VSI + 1) | M.toneW)
                    } else {
                        setTW(VSI, TW(VSI) | M.toneW)
                        setTW(VSI + 1, TW(VSI + 1) | M.toneW)
                    }
                } else if (CHR(VSI) == K.u && CHR(VSI + 1) == K.a) ||
                            (CHR(VSI) == K.u && CHR(VSI + 1) == K.i) ||
                            (CHR(VSI) == K.u && CHR(VSI + 1) == K.u) ||
                            (CHR(VSI) == K.o && CHR(VSI + 1) == K.i) {
                    setTW(VSI, TW(VSI) | M.toneW)
                } else if (CHR(VSI) == K.i && CHR(VSI + 1) == K.o) ||
                            (CHR(VSI) == K.o && CHR(VSI + 1) == K.a) {
                    setTW(VSI + 1, TW(VSI + 1) | M.toneW)
                } else {
                    // don't do anything
                    tempDisableKey = true
                    isChanged = false
                    hCode = HookCode.doNothing
                }

                ii = VSI
                while ii < _index {
                    setHData(_index - 1 - ii, getCharacterCode(TW(ii)))
                    ii += 1
                }
            }

            return
        }

        hCode = HookCode.willProcess
        hBPC = 0

        ii = _index - 1
        while ii >= 0 {
            if ii < VSI { break }
            hBPC += 1
            switch CHR(ii) {
            case K.a, K.u, K.o:
                if TW(ii) & M.toneW != 0 {
                    // restore and disable temporary
                    if TW(ii) & M.standalone != 0 {
                        hCode = HookCode.willProcess
                        if CHR(ii) == K.u {
                            setTW(ii, K.w | ((TW(ii) & M.caps) != 0 ? M.caps : 0))
                        } else if CHR(ii) == K.o {
                            hCode = HookCode.restore
                            setTW(ii, K.o | ((TW(ii) & M.caps) != 0 ? M.caps : 0))
                            isRestoredW = true
                        }
                        setHData(_index - 1 - ii, TW(ii))
                    } else {
                        hCode = HookCode.restore
                        setTW(ii, TW(ii) & ~M.toneW)
                        setHData(_index - 1 - ii, TW(ii))
                        isRestoredW = true
                    }

                    tempDisableKey = true
                } else {
                    setTW(ii, TW(ii) | M.toneW)
                    setTW(ii, TW(ii) & ~M.tone)
                    setHData(_index - 1 - ii, getCharacterCode(TW(ii)))
                }
            default:
                setHData(_index - 1 - ii, getCharacterCode(TW(ii)))
            }
            ii -= 1
        }
        hNCC = hBPC
    }

    private mutating func reverseLastStandaloneChar(_ keyCode: UInt32, _ isCaps: Bool) {
        hCode = HookCode.willProcess
        hBPC = 0
        hNCC = 1
        hExt = 4
        setTW(_index - 1, keyCode | M.toneW | M.standalone | (isCaps ? M.caps : 0))
        setHData(0, getCharacterCode(TW(_index - 1)))
    }

    private mutating func checkForStandaloneChar(_ data: UInt32, _ isCaps: Bool, _ keyWillReverse: UInt32) {
        if CHR(_index - 1) == keyWillReverse && TW(_index - 1) & M.toneW != 0 {
            hCode = HookCode.willProcess
            hBPC = 1
            hNCC = 1
            setTW(_index - 1, data | (isCaps ? M.caps : 0))
            setHData(0, getCharacterCode(TW(_index - 1)))
            return
        }

        // check standalone w -> ư

        if _index > 0 && CHR(_index - 1) == K.u && keyWillReverse == K.o {
            insertKey(keyWillReverse, isCaps)
            reverseLastStandaloneChar(keyWillReverse, isCaps)
            return
        }

        if _index == 0 { // zero char
            insertKey(data, isCaps, false)
            reverseLastStandaloneChar(keyWillReverse, isCaps)
            return
        } else if _index == 1 { // 1 char
            i = 0
            while i < VietnameseData.standaloneWbad.count {
                if CHR(0) == VietnameseData.standaloneWbad[i] {
                    insertKey(data, isCaps)
                    return
                }
                i += 1
            }
            insertKey(data, isCaps, false)
            reverseLastStandaloneChar(keyWillReverse, isCaps)
            return
        } else if _index == 2 {
            i = 0
            while i < VietnameseData.doubleWAllowed.count {
                if CHR(0) == VietnameseData.doubleWAllowed[i][0] && CHR(1) == VietnameseData.doubleWAllowed[i][1] {
                    insertKey(data, isCaps, false)
                    reverseLastStandaloneChar(keyWillReverse, isCaps)
                    return
                }
                i += 1
            }
            insertKey(data, isCaps)
            return
        }

        insertKey(data, isCaps)
    }

    private mutating func upperCaseFirstCharacter() {
        if TypingWord[0] & M.caps == 0 {
            hCode = HookCode.willProcess
            hBPC = 0
            hNCC = 1
            TypingWord[0] |= M.caps
            setHData(0, getCharacterCode(TypingWord[0]))
            _upperCaseStatus = 0
            if vUseMacro != 0 && !hMacroKey.isEmpty {
                hMacroKey[0] |= M.caps
            }
        }
    }

    private mutating func handleMainKey(_ data: UInt32, _ isCaps: Bool) {
        // if is Z key, remove mark
        if IS_KEY_Z(data) {
            removeMark()
            if !isChanged {
                insertKey(data, isCaps)
            }
            return
        }

        if data == K.leftBracket { // standalone key [
            checkForStandaloneChar(data, isCaps, K.o)
            return
        }

        if data == K.rightBracket { // standalone key ]
            checkForStandaloneChar(data, isCaps, K.u)
            return
        }

        // if is D key
        if IS_KEY_D(data) {
            isCorect = false
            isChanged = false
            k = _index
            let consonantD = VietnameseData.consonantD
            i = 0
            while i < consonantD.count {
                if _index < consonantD[i].count {
                    i += 1
                    continue
                }
                isCorect = true
                checkCorrectVowel(consonantD, \.i, data)

                // allow d after consonant
                if !isCorect && _index - 2 >= 0 && CHR(_index - 1) == K.d && IS_CONSONANT(CHR(_index - 2)) {
                    isCorect = true
                }
                if isCorect {
                    isChanged = true
                    insertD(data, isCaps)
                    break
                }
                i += 1
            }

            if !isChanged {
                insertKey(data, isCaps)
            }
            return
        }

        // if is mark key
        if IS_MARK_KEY(data) {
            for vowelEntry in VietnameseData.vowelForMark {
                let charset = vowelEntry.value
                isCorect = false
                isChanged = false
                k = _index
                l = 0
                while l < charset.count {
                    if _index < charset[l].count {
                        l += 1
                        continue
                    }
                    isCorect = true
                    checkCorrectVowel(charset, \.l, data)

                    if isCorect {
                        isChanged = true
                        if IS_KEY_S(data) {
                            insertMark(M.mark1)
                        } else if IS_KEY_F(data) {
                            insertMark(M.mark2)
                        } else if IS_KEY_R(data) {
                            insertMark(M.mark3)
                        } else if IS_KEY_X(data) {
                            insertMark(M.mark4)
                        } else if IS_KEY_J(data) {
                            insertMark(M.mark5)
                        }
                        break
                    }
                    l += 1
                }

                if isCorect {
                    break
                }
            }

            if !isChanged {
                insertKey(data, isCaps)
            }

            return
        }

        // check Vowel
        if vInputType == 1 {
            i = _index - 1
            while i >= 0 {
                if CHR(i) == K.o || CHR(i) == K.a || CHR(i) == K.e {
                    VEI = i
                    break
                }
                i -= 1
            }
        }

        // keyForAEO keeps only the low 16 bits
        if vInputType != 1 {
            keyForAEO = data & 0xFFFF
        } else {
            keyForAEO = (data == K.k7 || data == K.k8) ? K.w : (data == K.k6 ? (TW(VEI) & 0xFFFF) : (data & 0xFFFF))
        }
        let charset = VietnameseData.vowelByKey[keyForAEO] ?? []
        isCorect = false
        isChanged = false
        k = _index
        i = 0
        while i < charset.count {
            if _index < charset[i].count {
                i += 1
                continue
            }
            isCorect = true
            checkCorrectVowel(charset, \.i, data)

            if isCorect {
                isChanged = true
                if IS_KEY_DOUBLE(data) {
                    insertAOE(keyForAEO, isCaps)
                } else if IS_KEY_W(data) {
                    if vInputType == 1 {
                        j = _index - 1
                        while j >= 0 {
                            if CHR(j) == K.o || CHR(j) == K.u || CHR(j) == K.a || CHR(j) == K.e {
                                VEI = j
                                break
                            }
                            j -= 1
                        }
                        if (data == K.k7 && CHR(VEI) == K.a && (VEI - 1 >= 0 ? CHR(VEI - 1) != K.u : true)) ||
                            (data == K.k8 && (CHR(VEI) == K.o || CHR(VEI) == K.u)) {
                            break
                        }
                    }
                    insertW(keyForAEO, isCaps)
                }
                break
            }
            i += 1
        }

        if !isChanged {
            if data == K.w && vInputType != 2 {
                checkForStandaloneChar(data, isCaps, K.u)
            } else {
                insertKey(data, isCaps)
            }
        }
    }

    private mutating func handleQuickTelex(_ data: UInt32, _ isCaps: Bool) {
        hCode = HookCode.willProcess
        hBPC = 1
        hNCC = 2
        let quick = VietnameseData.quickTelexByKey[data] ?? [0, 0]
        setHData(1, quick[0] | (isCaps ? M.caps : 0))
        setHData(0, quick[1] | (isCaps ? M.caps : 0))
        insertKey(quick[1], isCaps, false)
    }

    /// Differs from the fixtures (see `FixtureExceptions`): no restore when `KeyStates` lacks the
    /// word's first keys (`_keyStatesIncomplete`). Restoring would delete the whole word (`hBPC = _index`)
    /// but retype only the remembered keys, losing letters: `sapce maf` ⌫×6 `pace ` gives "pace " instead
    /// of "sâpce ".
    private mutating func checkRestoreIfWrongSpelling(_ handleCode: Int) -> Bool {
        if _keyStatesIncomplete { return false }
        ii = 0
        while ii < _index {
            if !IS_CONSONANT(CHR(ii)) &&
                (TW(ii) & M.mark != 0 || TW(ii) & M.tone != 0 || TW(ii) & M.toneW != 0) {
                hCode = handleCode
                hBPC = _index
                hNCC = _stateIndex
                i = 0
                while i < _stateIndex {
                    setTW(i, KeyStates[min(i, Self.maxBuff - 1)])
                    setHData(_stateIndex - 1 - i, TW(i))
                    i += 1
                }
                _index = _stateIndex
                return true
            }
            ii += 1
        }
        return false
    }

    private mutating func vTempOffSpellChecking() {
        if _useSpellCheckingBefore {
            vCheckSpelling = vCheckSpelling != 0 ? 0 : 1
        }
    }

    private mutating func vSetCheckSpelling() {
        _useSpellCheckingBefore = vCheckSpelling != 0
    }

    private mutating func vTempOffEngine(_ off: Bool = true) {
        _willTempOffEngine = off
    }

    private mutating func checkQuickConsonant() -> Bool {
        if _index <= 1 { return false }
        // A quick start/end consonant adds one character to the word (two if both apply). With the 32-slot
        // buffer full, `_index` can't grow, so a garbage character from `hData[31]` would overwrite the last
        // letter, or `hNCC` = 33 would type nothing. Skip words of 30+ characters; they aren't Vietnamese anyway.
        if _index >= Self.maxBuff - 2 { return false }
        l = 0
        if _index > 0 {
            if vQuickStartConsonant != 0, let start = VietnameseData.quickStartConsonantByKey[CHR(0)] {
                hCode = HookCode.restore
                hBPC = _index
                hNCC = _index + 1
                if _index < Self.maxBuff - 1 {
                    _index += 1
                }
                // right shift
                i = _index - 1
                while i >= 2 {
                    setTW(i, TW(i - 1))
                    i -= 1
                }
                setTW(1, start[1] | ((TW(0) & M.caps) != 0 && (TW(2) & M.caps) != 0 ? M.caps : 0))
                setTW(0, start[0] | ((TW(0) & M.caps) != 0 ? M.caps : 0))
                l = 1
            }
            if vQuickEndConsonant != 0 &&
                (_index - 2 >= 0 && !IS_CONSONANT(CHR(_index - 2))),
               let end = VietnameseData.quickEndConsonantByKey[CHR(_index - 1)] {
                hCode = HookCode.restore
                if l == 1 {
                    hNCC += 1
                } else {
                    hBPC = 1
                    hNCC = 2
                }
                if _index < Self.maxBuff - 1 {
                    _index += 1
                }
                setTW(_index - 1, end[1] | ((TW(_index - 2) & M.caps) != 0 ? M.caps : 0))
                setTW(_index - 2, end[0] | ((TW(_index - 2) & M.caps) != 0 ? M.caps : 0))

                l = 1
            }
            if l == 1 {
                _hasHandleQuickConsonant = true
                i = _index - 1
                while i >= 0 {
                    setHData(_index - 1 - i, getCharacterCode(TW(i)))
                    i -= 1
                }
                return true
            }
        }
        return false
    }

    // MARK: - Macros

    /// Tracks macro input while Vietnamese typing is off.
    private mutating func vEnglishMode(isMouse: Bool, data: UInt32, isCaps: Bool, otherControlKey: Bool) {
        hCode = HookCode.doNothing
        if isMouse || (otherControlKey && !isCaps) {
            hMacroKey.removeAll(keepingCapacity: true)
            _willTempOffEngine = false
        } else if data == K.space {
            if !_hasHandledMacro && findMacro() {
                hCode = HookCode.replaceMacro
                hBPC = hMacroKey.count
            }
            hMacroKey.removeAll(keepingCapacity: true)
            _willTempOffEngine = false
        } else if data == K.delete {
            if hMacroKey.count > 0 {
                hMacroKey.removeLast()
            } else {
                _willTempOffEngine = false
            }
        } else {
            if isWordBreak(isMouse: false, data: data) && !Self.charKeyCode.contains(data) {
                hMacroKey.removeAll(keepingCapacity: true)
                _willTempOffEngine = false
            } else {
                if !_willTempOffEngine {
                    hMacroKey.append(data | (isCaps ? M.caps : 0))
                }
            }
        }
    }

    /// Looks up `hMacroKey` and stores the expansion in `hMacroData`. Converts `hMacroKey` to character
    /// codes in place, even when nothing is found (kept to match the fixtures).
    private mutating func findMacro() -> Bool {
        var c = 0
        while c < hMacroKey.count {
            hMacroKey[c] = getCharacterCode(hMacroKey[c])
            c += 1
        }
        if let content = macroTable.contentCode(for: hMacroKey) {
            hMacroData = content
            return true
        }
        if vAutoCapsMacro != 0 {
            var macroFlag = false
            if hMacroKey.count > 1 && Self.modifyCaseUnicode(&hMacroKey[1], false) {
                macroFlag = true
                c = 2
                while c < hMacroKey.count {
                    _ = Self.modifyCaseUnicode(&hMacroKey[c], false)
                    c += 1
                }
            }

            if hMacroKey.count > 0 && Self.modifyCaseUnicode(&hMacroKey[0], false) {
                if let content = macroTable.contentCode(for: hMacroKey) {
                    hMacroData = content
                    c = 0
                    while c < hMacroData.count {
                        if c == 0 || macroFlag {
                            var kChar = VietnameseData.character(for: hMacroData[c])
                            if kChar != 0 {
                                // uppercase ASCII letters only
                                if kChar >= 0x61 && kChar <= 0x7A { kChar -= 0x20 }
                                hMacroData[c] = VietnameseData.characterKeyCode[UInt32(kChar)] ?? 0
                                c += 1
                                continue
                            }
                            if hMacroData[c] & M.charCode != 0 {
                                _ = Self.modifyCaseUnicode(&hMacroData[c], true)
                            }
                        }
                        c += 1
                    }
                    return true
                }
            }
        }
        return false
    }

    /// Changes the case of an engine character code in place; returns whether it changed.
    private static func modifyCaseUnicode(_ code: inout UInt32, _ isUpperCase: Bool) -> Bool {
        let charBuff = code
        if code & M.charCode == 0 { // for normal char
            code &= isUpperCase ? M.caps : ~M.caps
            return code != charBuff
        }
        // for unicode character
        for entry in VietnameseData.unicodeTable {
            var k = 0
            while k < entry.value.count {
                if UInt16(truncatingIfNeeded: code) == entry.value[k] {
                    if k % 2 == 0 && !isUpperCase {
                        k += 1
                    } else if k % 2 != 0 && isUpperCase {
                        k -= 1
                    }
                    code = UInt32(entry.value[min(k, entry.value.count - 1)]) | M.charCode
                    return code != charBuff
                }
                k += 1
            }
        }
        return false
    }

    /// Main entry point: processes one key or mouse event and fills the hook state.
    private mutating func vKeyHandleEvent(isMouse: Bool, data: UInt32, capsStatus: Int = 0, otherControlKey: Bool = false) {
        _isCaps = capsStatus == 1 || capsStatus == 2 // shift / caps lock
        if (IS_NUMBER_KEY(data) && capsStatus == 1) ||
            otherControlKey || isWordBreak(isMouse: isMouse, data: data) || (_index == 0 && IS_NUMBER_KEY(data)) {
            hCode = HookCode.doNothing
            hBPC = 0
            hNCC = 0
            hExt = 1 // word break

            // check macro feature
            if vUseMacro != 0 && isMacroBreakCode(data) && !_hasHandledMacro && findMacro() {
                hCode = HookCode.replaceMacro
                hBPC = hMacroKey.count
                _hasHandledMacro = true
            } else if (vQuickStartConsonant != 0 || vQuickEndConsonant != 0) && !tempDisableKey && isMacroBreakCode(data) {
                _ = checkQuickConsonant()
            } else if vRestoreIfWrongSpelling != 0 && isWordBreak(isMouse: isMouse, data: data) { // restore key if wrong spelling with break-key
                if !tempDisableKey && vCheckSpelling != 0 {
                    checkSpelling(true) // force check spelling
                }
                if tempDisableKey && !checkRestoreIfWrongSpelling(HookCode.restoreAndStartNewSession) {
                    hCode = HookCode.doNothing
                }
            }

            _isCharKeyCode = !isMouse && Self.charKeyCode.contains(data)
            if !_isCharKeyCode { // clear all line cache
                _specialChar.removeAll(keepingCapacity: true)
                _typingStates.removeAll()
            } else { // check and save current word
                if _spaceCount > 0 {
                    saveWord(K.space, _spaceCount)
                    _spaceCount = 0
                } else {
                    saveWord()
                }
                _specialChar.append(data | (_isCaps ? M.caps : 0))
                hExt = 3 // normal word
            }

            if hCode == HookCode.doNothing {
                startNewSession()
                vCheckSpelling = _useSpellCheckingBefore ? 1 : 0
                _willTempOffEngine = false
            } else if hCode == HookCode.replaceMacro || _hasHandleQuickConsonant {
                _index = 0
            }

            // insert key for macro function
            if vUseMacro != 0 {
                if _isCharKeyCode {
                    hMacroKey.append(data | (_isCaps ? M.caps : 0))
                } else {
                    hMacroKey.removeAll(keepingCapacity: true)
                }
            }

            if vUpperCaseFirstChar != 0 {
                // "!" and "?" (Shift+1, Shift+/) end a sentence too
                if data == K.dot || (capsStatus == 1 && (data == K.k1 || data == K.slash)) {
                    _upperCaseStatus = 1
                } else if data == K.enter || data == K.returnKey {
                    _upperCaseStatus = 2
                } else {
                    _upperCaseStatus = 0
                }
            }
        } else if data == K.space {
            if !tempDisableKey && vCheckSpelling != 0 {
                checkSpelling(true) // force check spelling
            }
            if vUseMacro != 0 && !_hasHandledMacro && findMacro() { // macro
                hCode = HookCode.replaceMacro
                hBPC = hMacroKey.count
                _spaceCount += 1
                _hasHandledMacro = true
            } else if (vQuickStartConsonant != 0 || vQuickEndConsonant != 0) && !tempDisableKey && checkQuickConsonant() {
                _spaceCount += 1
            } else if vRestoreIfWrongSpelling != 0 && tempDisableKey && !_hasHandledMacro { // restore key if wrong spelling
                if !checkRestoreIfWrongSpelling(HookCode.restore) {
                    hCode = HookCode.doNothing
                }
                _spaceCount += 1
            } else { // do nothing with SPACE KEY
                hCode = HookCode.doNothing
                _spaceCount += 1
            }
            if vUseMacro != 0 {
                hMacroKey.removeAll(keepingCapacity: true)
            }
            if vUpperCaseFirstChar != 0 && _upperCaseStatus == 1 {
                _upperCaseStatus = 2
            }
            // save word
            if _spaceCount == 1 {
                if _specialChar.count > 0 {
                    saveSpecialChar()
                } else {
                    saveWord()
                }
            }
            vCheckSpelling = _useSpellCheckingBefore ? 1 : 0
            _willTempOffEngine = false
        } else if data == K.delete {
            hCode = HookCode.doNothing
            hExt = 2 // delete
            if _specialChar.count > 0 {
                _specialChar.removeLast()
                if _specialChar.count == 0 {
                    restoreLastTypingState()
                }
            } else if _spaceCount > 0 { // previous char is space
                _spaceCount -= 1
                if _spaceCount == 0 { // restore word
                    restoreLastTypingState()
                }
            } else {
                if _stateIndex > 0 {
                    _stateIndex -= 1
                }
                if _index > 0 {
                    _index -= 1
                    if _longWordHelper.count > 0 {
                        // right shift
                        i = Self.maxBuff - 1
                        while i > 0 {
                            TypingWord[i] = TypingWord[i - 1]
                            i -= 1
                        }
                        TypingWord[0] = _longWordHelper.removeLast()
                        _index += 1
                    }
                    if vCheckSpelling != 0 {
                        checkSpelling()
                    }
                }
                if vUseMacro != 0 && hMacroKey.count > 0 {
                    hMacroKey.removeLast()
                }

                hBPC = 0
                hNCC = 0
                hExt = 2 // delete key
                if _index == 0 {
                    startNewSession()
                    _specialChar.removeAll(keepingCapacity: true)
                    restoreLastTypingState()
                } else { // keep checking grammar
                    checkGrammar(1)
                }
            }
        } else { // START AND CHECK KEY
            if _willTempOffEngine {
                hCode = HookCode.doNothing
                hExt = 3
                return
            }
            if _spaceCount > 0 {
                hBPC = 0
                hNCC = 0
                hExt = 0
                startNewSession()
                // keep counting spaces
                saveWord(K.space, _spaceCount)
                _spaceCount = 0
            } else if _specialChar.count > 0 {
                saveSpecialChar()
            }

            insertState(data, _isCaps) // save state

            if !IS_SPECIALKEY(data) || tempDisableKey { // do nothing
                if vQuickTelex != 0 && IS_QUICK_TELEX_KEY(data) {
                    handleQuickTelex(data, _isCaps)
                    return
                } else {
                    hCode = HookCode.doNothing
                    hBPC = 0
                    hNCC = 0
                    hExt = 3 // normal key
                    insertKey(data, _isCaps)
                }
            } else { // check and update key
                // restore state
                hCode = HookCode.doNothing
                hExt = 3 // normal key
                handleMainKey(data, _isCaps)
            }

            if vFreeMark == 0 && !IS_KEY_D(data) {
                if hCode == HookCode.doNothing {
                    checkGrammar(-1)
                } else {
                    checkGrammar(0)
                }
            }

            if hCode == HookCode.restore {
                insertKey(data, _isCaps)
                _stateIndex -= 1
            }

            // insert or replace key for macro feature
            if vUseMacro != 0 {
                if hCode == HookCode.doNothing {
                    hMacroKey.append(data | (_isCaps ? M.caps : 0))
                } else if hCode == HookCode.willProcess || hCode == HookCode.restore {
                    i = 0
                    while i < hBPC {
                        if hMacroKey.count > 0 {
                            hMacroKey.removeLast()
                        }
                        i += 1
                    }
                    i = _index - hBPC
                    while i < hNCC + (_index - hBPC) {
                        hMacroKey.append(TW(i))
                        i += 1
                    }
                }
            }

            if vUpperCaseFirstChar != 0 {
                if _index == 1 && _upperCaseStatus == 2 {
                    upperCaseFirstCharacter()
                }
                _upperCaseStatus = 0
            }

            // case [ ]
            if IS_BRACKET_KEY(data) && (IS_BRACKET_KEY(hData[0] & 0xFFFF) || vInputType == 2 || vInputType == 3) {
                if _index - (hCode == HookCode.willProcess ? hBPC : 0) > 0 {
                    _index -= 1
                    saveWord()
                }
                _index = 0
                tempDisableKey = false
                _stateIndex = 0
                hExt = 3
                _specialChar.append(data | (_isCaps ? M.caps : 0))
            }
        }
    }
}
