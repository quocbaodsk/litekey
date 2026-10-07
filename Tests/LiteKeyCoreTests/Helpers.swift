import LiteKeyEngine
@testable import LiteKeyCore

/// Fake engine: returns preset output and records calls.
final class FakeEngine: TypingEngine {
    var nextOutput = EngineOutput()
    var configs: [EngineConfig] = []
    var sessions = 0
    var tempOffSpellingCount = 0
    var tempOffEngineCount = 0
    var keys: [(code: UInt16, caps: CapsState, other: Bool)] = []

    func configure(_ config: EngineConfig) { configs.append(config) }
    func newSession() { sessions += 1 }
    func tempOffSpellChecking() { tempOffSpellingCount += 1 }
    func tempOffEngine() { tempOffEngineCount += 1 }
    var macroTables: [MacroTable] = []
    var englishKeys: [UInt16] = []
    var nextEnglishOutput = EngineOutput()
    func setMacros(_ table: MacroTable) { macroTables.append(table) }
    func handleEnglishModeKey(code: UInt16, caps: CapsState, otherModifier: Bool, into output: inout EngineOutput) {
        englishKeys.append(code)
        output = nextEnglishOutput
    }
    func handleKey(code: UInt16, caps: CapsState, otherModifier: Bool, into output: inout EngineOutput) {
        keys.append((code, caps, otherModifier))
        output = nextOutput
    }
}

/// Readable form of a plan for test comparisons.
enum Step: Equatable {
    case key(UInt16, ModifierFlags)
    case text(String)
    case sleep(UInt32)
    case repost
}

extension InjectionPlan {
    var readable: [Step] {
        steps.map { step in
            switch step {
            case let .key(code, flags): return .key(code, flags)
            case let .text(start, count):
                return .text(String(decoding: text[start..<start + count], as: UTF16.self))
            case let .sleep(us): return .sleep(us)
            case .repostOriginal: return .repost
            }
        }
    }
}

let backspace = Step.key(KeyCode.delete, [])
let shiftLeft = Step.key(KeyCode.leftArrow, .shift)
let forwardDelete = Step.key(KeyCode.forwardDelete, [])
let emptyChar = Step.text("\u{202F}")
let niceSpace = Step.text("\u{200C}")

/// Engine output: delete `backspaces`, type `text` (Unicode characters).
func replace(_ backspaces: Int, _ text: String, noEmpty: Bool = false) -> EngineOutput {
    EngineOutput(action: .replace, backspaces: backspaces,
                 characters: text.utf16.map { OutputCharacter(unit: $0) },
                 noEmptyCharPrefix: noEmpty)
}

/// Engine output for an invalid word: retype `keys` (plain keys), then the restore key.
func restore(_ backspaces: Int, keys: [(UInt16, Character)], restore: OutputCharacter) -> EngineOutput {
    EngineOutput(action: .replace, backspaces: backspaces,
                 characters: keys.map { OutputCharacter(unit: String($0.1).utf16.first!, keyCode: $0.0) },
                 restoreKey: restore)
}
