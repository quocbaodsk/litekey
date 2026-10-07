import XCTest
import LiteKeyEngine
@testable import LiteKeyCore

/// Exercises the full key path with the real engine: `KeyEventProcessor` → `VietnameseEngine` →
/// `InjectionPlanner` → a fake screen (executes the plan like `StepExecutor`, without delays).
final class EndToEndTypingTests: XCTestCase {
    /// US layout key codes
    private static let codes: [Character: UInt16] = {
        let chars = Array("asdfhgzxcvbqweryt123465=97-80]ou[ip lj'k;\\,/nm.`")
        let codes: [UInt16] = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25,
                               26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 49, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 50]
        return Dictionary(uniqueKeysWithValues: zip(chars, codes))
    }()

    private func type(_ keys: String, preferences: Preferences = Preferences(),
                      context: AppContext = AppContext(bundleID: "com.google.Chrome", rules: .builtIn, preferences: Preferences()),
                      macros: MacroTable = MacroTable()) -> String {
        var processor = KeyEventProcessor(engine: VietnameseEngine(config: preferences.engineConfig),
                                          preferences: preferences, context: context)
        processor.update(macros: macros)
        let chars = Dictionary(uniqueKeysWithValues: Self.codes.map { ($1, $0) })
        var plan = InjectionPlan()
        var screen: [UInt16] = []
        for ch in keys {
            let lower = Character(ch.lowercased())
            guard let code = Self.codes[lower] else { XCTFail("unknown key \(ch)"); continue }
            let flags: ModifierFlags = ch.isUppercase ? .shift : []
            let decision = processor.handle(KeyEvent(kind: .keyDown, keyCode: code, flags: flags), plan: &plan)
            if decision.passThrough {
                screen.append(contentsOf: String(ch).utf16)
                continue
            }
            for step in plan.steps {
                switch step {
                case let .key(keyCode, flags):
                    if keyCode == KeyCode.delete {
                        if !screen.isEmpty { screen.removeLast() }
                    } else if let ch = chars[keyCode] {
                        // Trigger key re-sent after a macro
                        screen.append(contentsOf: (flags.contains(.shift) ? ch.uppercased() : String(ch)).utf16)
                    }
                case let .text(start, count):
                    screen.append(contentsOf: plan.text[start..<start + count])
                case .repostOriginal:
                    screen.append(contentsOf: String(ch).utf16)
                case .sleep:
                    break
                }
            }
            _ = processor.handle(KeyEvent(kind: .keyUp, keyCode: code, flags: flags), plan: &plan)
        }
        return String(decoding: screen, as: UTF16.self)
    }

    func testToiLa() {
        XCTAssertEqual(type("tooi laf "), "tôi là ")
        XCTAssertEqual(type("Tooi laf baor pro nef "), "Tôi là bảo pro nè ")
        XCTAssertEqual(type("tooi laf ", context: AppContext(bundleID: "com.apple.TextEdit", rules: .builtIn,
                                                              preferences: Preferences())), "tôi là ")
    }

    func testRealWorldSentenceInVSCode() {
        // Real-world sentence typed in VS Code: engine + planner produce the right text, including deleting and retyping "as"
        let vscode = AppContext(bundleID: "com.microsoft.VSCode", rules: .builtIn, preferences: Preferences())
        XCTAssertEqual(type("tooi laf baor pro ddang laf gox trong laf laf as", context: vscode),
                       "tôi là bảo pro đang là gõ trong là là á")
    }

    func testSentence() {
        XCTAssertEqual(type("Tooi ddang gox tieesng Vieejt, thuwr nghieejm class string window."),
                       "Tôi đang gõ tiếng Việt, thử nghiệm class string window.")
    }

    func testMacroInVietnameseMode() {
        let macros = MacroTable(macros: [Macro(text: "vn", content: "Việt Nam"), Macro(text: "btw", content: "by the way")])
        XCTAssertEqual(type("tooi owr vn ", macros: macros), "tôi ở Việt Nam ")
        XCTAssertEqual(type("btw, ok", macros: macros), "by the way, ok")
        var off = Preferences()
        off.useMacro = false
        XCTAssertEqual(type("tooi owr vn ", preferences: off, macros: macros), "tôi ở vn ")
    }

    func testEmptyCharIsRemovedByExtraBackspace() {
        // The empty char is removed by one extra backspace, leaving the visible text unchanged
        for id in ["com.apple.TextEdit", "com.microsoft.VSCode", "com.apple.Terminal"] {
            XCTAssertEqual(type("tooi laf ", context: AppContext(bundleID: id, rules: .builtIn, preferences: Preferences())),
                           "tôi là ", id)
        }
    }

    func testClickClearsEnglishModeMacroBuffer() {
        var prefs = Preferences()
        prefs.vietnamese = false
        prefs.useMacroInEnglishMode = true
        for click in [false, true] {
            var p = KeyEventProcessor(engine: VietnameseEngine(config: prefs.engineConfig), preferences: prefs,
                                      context: AppContext(bundleID: "com.apple.TextEdit"))
            p.update(macros: MacroTable(macros: [Macro(text: "vn", content: "Việt Nam")]))
            var plan = InjectionPlan()
            _ = p.handle(KeyEvent(kind: .keyDown, keyCode: Self.codes["v"]!), plan: &plan)
            _ = p.handle(KeyEvent(kind: .keyDown, keyCode: Self.codes["n"]!), plan: &plan)
            if click { _ = p.handle(KeyEvent(kind: .mouseDown), plan: &plan) }
            let space = p.handle(KeyEvent(kind: .keyDown, keyCode: KeyCode.space), plan: &plan)
            // Without the click the macro expands; after it, Space is a plain space at the new spot
            XCTAssertEqual(space.passThrough, click)
        }
    }

    func testClickInExcludedAppStartsNewWord() {
        var prefs = Preferences()
        prefs.excludedApps = ["com.apple.Terminal"]
        var p = KeyEventProcessor(engine: VietnameseEngine(config: prefs.engineConfig), preferences: prefs,
                                  context: AppContext(bundleID: "com.apple.Terminal"))
        var plan = InjectionPlan()
        _ = p.handle(KeyEvent(kind: .keyDown, keyCode: Self.codes["a"]!), plan: &plan)
        XCTAssertEqual(p.handle(KeyEvent(kind: .mouseDown), plan: &plan), .pass)
        // Back in a regular app the old word is gone: "a" alone does not become "â"
        p.update(context: AppContext(bundleID: "com.apple.TextEdit"))
        XCTAssertTrue(p.handle(KeyEvent(kind: .keyDown, keyCode: Self.codes["a"]!), plan: &plan).passThrough)
    }
}
