import XCTest
import LiteKeyEngine
@testable import LiteKeyCore

final class KeyEventProcessorTests: XCTestCase {
    private var engine: FakeEngine!
    private var plan = InjectionPlan()
    private let option = ModifierFlags(rawValue: 0x80120)
    private let ctrl = ModifierFlags(rawValue: 0x40101)
    private let cmd = ModifierFlags(rawValue: 0x100108)
    private let none = ModifierFlags(rawValue: 0x100)

    override func setUp() {
        engine = FakeEngine()
        plan = InjectionPlan()
    }

    private func makeProcessor(_ configure: (inout Preferences) -> Void = { _ in }) -> KeyEventProcessor<FakeEngine> {
        var prefs = Preferences()
        prefs.fixRecommendBrowser = false
        configure(&prefs)
        return KeyEventProcessor(engine: engine, preferences: prefs,
                                 context: AppContext(bundleID: "com.apple.TextEdit"))
    }

    private func keyDown(_ code: UInt16, _ flags: ModifierFlags = []) -> KeyEvent {
        KeyEvent(kind: .keyDown, keyCode: code, flags: flags)
    }

    func testInitConfiguresEngine() {
        _ = makeProcessor { $0.inputType = .vni; $0.quickTelex = true }
        XCTAssertEqual(engine.configs.last?.inputType, .vni)
        XCTAssertEqual(engine.configs.last?.quickTelex, true)
    }

    func testReplaceIsSwallowedWithPlan() {
        var p = makeProcessor()
        engine.nextOutput = replace(1, "â")
        XCTAssertEqual(p.handle(keyDown(0), plan: &plan), .swallow)
        XCTAssertEqual(plan.readable, [backspace, .text("â")])
    }

    func testPassFromEngine() {
        var p = makeProcessor()
        XCTAssertEqual(p.handle(keyDown(0), plan: &plan), .pass)
        XCTAssertTrue(plan.isEmpty)
    }

    func testCapsAndOtherControl() {
        var p = makeProcessor()
        _ = p.handle(keyDown(0, [.shift, .capsLock]), plan: &plan)
        _ = p.handle(keyDown(0, [.capsLock]), plan: &plan)
        _ = p.handle(keyDown(0, [.command]), plan: &plan)
        _ = p.handle(keyDown(0, [.function]), plan: &plan)
        XCTAssertEqual(engine.keys.map(\.caps), [.shift, .capsLock, .none, .none])
        XCTAssertEqual(engine.keys.map(\.other), [false, false, true, true])
    }

    func testKeyUpNeverReachesEngine() {
        var p = makeProcessor()
        XCTAssertEqual(p.handle(KeyEvent(kind: .keyUp, keyCode: 0), plan: &plan), .pass)
        XCTAssertTrue(engine.keys.isEmpty)
    }

    func testEnglishModePassesWithoutEngine() {
        var p = makeProcessor { $0.vietnamese = false }
        engine.nextOutput = replace(1, "â")
        XCTAssertEqual(p.handle(keyDown(0), plan: &plan), .pass)
        XCTAssertTrue(engine.keys.isEmpty)
    }

    func testClickStartsNewWordInEnglishModeToo() {
        // The real-engine effect (macro buffer cleared) is in EndToEndTypingTests
        var p = makeProcessor { $0.vietnamese = false; $0.useMacroInEnglishMode = true }
        let sessions = engine.sessions
        XCTAssertEqual(p.handle(KeyEvent(kind: .mouseDown), plan: &plan), .pass)
        XCTAssertEqual(engine.sessions, sessions + 1)
    }

    func testExcludedAppPasses() {
        var p = makeProcessor { $0.excludedApps = ["com.apple.TextEdit"] }
        engine.nextOutput = replace(1, "â")
        XCTAssertEqual(p.handle(keyDown(0), plan: &plan), .pass)
        XCTAssertTrue(engine.keys.isEmpty)
    }

    func testSpotlightOverExcludedAppReachesEngine() {
        var p = makeProcessor { $0.excludedApps = ["com.apple.TextEdit"] }
        var ctx = p.context
        ctx.spotlightActive = true
        ctx.overlayBundleID = AppRules.spotlight
        p.update(context: ctx)
        XCTAssertFalse(p.context.isExcluded)
        engine.nextOutput = replace(1, "â")
        XCTAssertEqual(p.handle(keyDown(0), plan: &plan), .swallow)
        // Spotlight closes: the excluded app is English again
        ctx.spotlightActive = false
        p.update(context: ctx)
        XCTAssertTrue(p.context.isExcluded)
    }

    func testPassThroughAppPasses() {
        var p = makeProcessor()
        p.update(context: AppContext(bundleID: "com.microsoft.rdc.macos", rules: .builtIn, preferences: p.preferences))
        engine.nextOutput = replace(1, "â")
        XCTAssertEqual(p.handle(keyDown(0), plan: &plan), .pass)
        XCTAssertTrue(engine.keys.isEmpty)
    }

    func testKeyRepeatPassesAndStartsNewWord() {
        var p = makeProcessor()
        engine.nextOutput = replace(1, "ô")
        let sessions = engine.sessions
        let d = p.handle(KeyEvent(kind: .keyDown, keyCode: 31, isRepeat: true), plan: &plan)
        XCTAssertEqual(d, .pass)
        XCTAssertTrue(plan.isEmpty)
        XCTAssertTrue(engine.keys.isEmpty)
        XCTAssertEqual(engine.sessions, sessions + 1)
    }

    func testKeyRepeatInExcludedAppPassesWithoutEngine() {
        var p = makeProcessor { $0.excludedApps = ["com.apple.TextEdit"] }
        XCTAssertEqual(p.handle(KeyEvent(kind: .keyDown, keyCode: 31, isRepeat: true), plan: &plan), .pass)
        XCTAssertTrue(engine.keys.isEmpty)
    }

    func testKeyRepeatInEnglishModeStillFeedsMacros() {
        // Only Vietnamese mode skips repeats; the English-mode macro buffer sees every key
        var p = makeProcessor { $0.vietnamese = false; $0.useMacroInEnglishMode = true }
        _ = p.handle(KeyEvent(kind: .keyDown, keyCode: 31, isRepeat: true), plan: &plan)
        XCTAssertEqual(engine.englishKeys, [31])
    }

    func testHotkeyKeyRepeatDoesNotToggleAgain() {
        var p = makeProcessor { $0.hotkey = .optionZ }
        _ = p.handle(KeyEvent(kind: .flagsChanged, flags: option), plan: &plan)
        _ = p.handle(keyDown(KeyCode.z, option), plan: &plan)
        XCTAssertFalse(p.preferences.vietnamese)
        _ = p.handle(KeyEvent(kind: .keyDown, keyCode: KeyCode.z, flags: option, isRepeat: true), plan: &plan)
        XCTAssertFalse(p.preferences.vietnamese)
    }

    func testBackspaceRepeatReachesEngine() {
        var p = makeProcessor()
        _ = p.handle(KeyEvent(kind: .keyDown, keyCode: KeyCode.delete, isRepeat: true), plan: &plan)
        XCTAssertEqual(engine.keys.map(\.code), [KeyCode.delete])
    }

    func testHotkeyIgnoredWhileInputSourceTurnsVietnameseOff() {
        var p = makeProcessor()
        var ctx = p.context
        ctx.inputSourceIsEnglish = false
        p.update(context: ctx)
        let ctrlShift = ModifierFlags(rawValue: 0x60103)
        _ = p.handle(KeyEvent(kind: .flagsChanged, flags: ctrl), plan: &plan)
        _ = p.handle(KeyEvent(kind: .flagsChanged, flags: ctrlShift), plan: &plan)
        let d = p.handle(KeyEvent(kind: .flagsChanged, flags: ModifierFlags(rawValue: 0x20102)), plan: &plan)
        XCTAssertEqual(d, .pass)
        XCTAssertTrue(p.preferences.vietnamese)
    }

    func testKeyHotkeyPassesWhileInputSourceTurnsVietnameseOff() {
        var p = makeProcessor { $0.hotkey = .optionZ }
        var ctx = p.context
        ctx.inputSourceIsEnglish = false
        p.update(context: ctx)
        _ = p.handle(KeyEvent(kind: .flagsChanged, flags: option), plan: &plan)
        XCTAssertEqual(p.handle(keyDown(KeyCode.z, option), plan: &plan), .pass)
        XCTAssertTrue(p.preferences.vietnamese)
    }

    func testHotkeyWorksUnderOtherInputSourceWhenOptionOff() {
        var p = makeProcessor { $0.hotkey = .optionZ; $0.disableOnNonEnglishInputSource = false }
        var ctx = p.context
        ctx.inputSourceIsEnglish = false
        p.update(context: ctx)
        _ = p.handle(KeyEvent(kind: .flagsChanged, flags: option), plan: &plan)
        _ = p.handle(keyDown(KeyCode.z, option), plan: &plan)
        XCTAssertFalse(p.preferences.vietnamese)
    }

    func testExclusionFollowsPreferenceUpdate() {
        var p = makeProcessor()
        var prefs = p.preferences
        prefs.excludedApps = ["com.apple.TextEdit"]
        p.update(preferences: prefs)
        XCTAssertTrue(p.context.isExcluded)
    }

    func testOptionZTogglesAndSwallows() {
        var p = makeProcessor { $0.hotkey = .optionZ }
        let sessions = engine.sessions
        _ = p.handle(KeyEvent(kind: .flagsChanged, keyCode: 58, flags: option), plan: &plan)
        let d = p.handle(keyDown(KeyCode.z, option), plan: &plan)
        XCTAssertEqual(d, KeyDecision(passThrough: false, languageToggled: true))
        XCTAssertFalse(p.preferences.vietnamese)
        XCTAssertEqual(engine.sessions, sessions + 1)
        XCTAssertTrue(engine.keys.isEmpty)
    }

    func testDefaultModifierHotkeySwallowsRelease() {
        var p = makeProcessor()
        let ctrlShift = ModifierFlags(rawValue: 0x60103)
        _ = p.handle(KeyEvent(kind: .flagsChanged, flags: ctrl), plan: &plan)
        _ = p.handle(KeyEvent(kind: .flagsChanged, flags: ctrlShift), plan: &plan)
        let d = p.handle(KeyEvent(kind: .flagsChanged, flags: ModifierFlags(rawValue: 0x20102)), plan: &plan)
        XCTAssertEqual(d, KeyDecision(passThrough: false, languageToggled: true))
        XCTAssertFalse(p.preferences.vietnamese)
    }

    func testHotkeyWorksInEnglishMode() {
        var p = makeProcessor { $0.vietnamese = false; $0.hotkey = .optionZ }
        _ = p.handle(KeyEvent(kind: .flagsChanged, flags: option), plan: &plan)
        _ = p.handle(keyDown(KeyCode.z, option), plan: &plan)
        XCTAssertTrue(p.preferences.vietnamese)
    }

    func testTempOffSpellingWithControl() {
        var p = makeProcessor { $0.tempOffSpellingWithControl = true }
        _ = p.handle(KeyEvent(kind: .flagsChanged, flags: ctrl), plan: &plan)
        _ = p.handle(KeyEvent(kind: .flagsChanged, flags: none), plan: &plan)
        XCTAssertEqual(engine.tempOffSpellingCount, 1)
    }

    func testTempOffSpellingDisabledByDefault() {
        var p = makeProcessor()
        _ = p.handle(KeyEvent(kind: .flagsChanged, flags: ctrl), plan: &plan)
        _ = p.handle(KeyEvent(kind: .flagsChanged, flags: none), plan: &plan)
        XCTAssertEqual(engine.tempOffSpellingCount, 0)
    }

    func testTempOffEngineWithCommand() {
        var p = makeProcessor { $0.tempOffEngineWithCommand = true }
        _ = p.handle(KeyEvent(kind: .flagsChanged, flags: cmd), plan: &plan)
        _ = p.handle(KeyEvent(kind: .flagsChanged, flags: none), plan: &plan)
        XCTAssertEqual(engine.tempOffEngineCount, 1)
    }

    func testTempOffNotTriggeredAfterShortcut() {
        var p = makeProcessor { $0.tempOffEngineWithCommand = true }
        _ = p.handle(KeyEvent(kind: .flagsChanged, flags: cmd), plan: &plan)
        _ = p.handle(keyDown(8, cmd), plan: &plan)  // ⌘C
        _ = p.handle(KeyEvent(kind: .flagsChanged, flags: none), plan: &plan)
        XCTAssertEqual(engine.tempOffEngineCount, 0)
    }

    func testMouseStartsNewSession() {
        var p = makeProcessor()
        let sessions = engine.sessions
        let d = p.handle(KeyEvent(kind: .mouseDown), plan: &plan)
        XCTAssertTrue(d.passThrough)
        XCTAssertEqual(engine.sessions, sessions + 1)
        _ = p.handle(KeyEvent(kind: .mouseDragged), plan: &plan)
        XCTAssertEqual(engine.sessions, sessions + 2)
    }

    func testNonEnglishInputSourcePasses() {
        var p = makeProcessor()
        var ctx = p.context
        ctx.inputSourceIsEnglish = false
        p.update(context: ctx)
        engine.nextOutput = replace(1, "â")
        XCTAssertEqual(p.handle(keyDown(0), plan: &plan), .pass)
        XCTAssertTrue(engine.keys.isEmpty)

        var prefs = p.preferences
        prefs.disableOnNonEnglishInputSource = false
        p.update(preferences: prefs)
        XCTAssertEqual(p.handle(keyDown(0), plan: &plan), .swallow)
    }

    func testOffConsolePassesEverything() {
        var p = makeProcessor()
        var ctx = p.context
        ctx.sessionOnConsole = false
        p.update(context: ctx)
        _ = p.handle(KeyEvent(kind: .flagsChanged, flags: option), plan: &plan)
        XCTAssertEqual(p.handle(keyDown(KeyCode.z, option), plan: &plan), .pass)
        XCTAssertTrue(p.preferences.vietnamese)
    }

    func testLayoutCompatMapsKeyCodeBeforeEngineAndHotkey() {
        var p = makeProcessor { $0.layoutCompatibility = true }
        var ctx = p.context
        // Simulated Dvorak: physical key 31 (US "o") types "r", key 1 (US "s") types "o"
        ctx.layoutMap = KeyboardLayoutMap { code, _ in
            switch code { case 31: return "r"; case 1: return "o"; case 47: return "v"; default: return nil }
        }
        p.update(context: ctx)
        _ = p.handle(keyDown(31), plan: &plan)
        _ = p.handle(keyDown(1), plan: &plan)
        XCTAssertEqual(engine.keys.map(\.code), [15, 31])
    }

    func testLayoutCompatOff() {
        var p = makeProcessor()
        var ctx = p.context
        ctx.layoutMap = KeyboardLayoutMap { _, _ in "r" }
        p.update(context: ctx)
        _ = p.handle(keyDown(31), plan: &plan)
        XCTAssertEqual(engine.keys.map(\.code), [31])
    }

    func testContextChangeStartsNewSessionOnlyWhenAppChanges() {
        var p = makeProcessor()
        let sessions = engine.sessions
        var ctx = p.context
        ctx.spotlightActive = true
        p.update(context: ctx)
        XCTAssertEqual(engine.sessions, sessions)
        p.update(context: AppContext(bundleID: "com.apple.Terminal", rules: .builtIn, preferences: p.preferences))
        XCTAssertEqual(engine.sessions, sessions + 1)
    }

    func testInputSourceChangeStartsNewSession() {
        var p = makeProcessor()
        let sessions = engine.sessions
        var ctx = p.context
        ctx.inputSourceIsEnglish = false
        p.update(context: ctx)
        XCTAssertEqual(engine.sessions, sessions + 1)
        ctx.inputSourceIsEnglish = true
        p.update(context: ctx)
        XCTAssertEqual(engine.sessions, sessions + 2)
        ctx.layoutMap = KeyboardLayoutMap { _, _ in "q" }
        p.update(context: ctx)
        XCTAssertEqual(engine.sessions, sessions + 3)
        p.update(context: ctx)
        XCTAssertEqual(engine.sessions, sessions + 3)
    }

    func testClickWhileHoldingHotkeyDoesNotToggle() {
        var p = makeProcessor { $0.hotkey = .controlShift }
        _ = p.handle(KeyEvent(kind: .flagsChanged, flags: ModifierFlags(rawValue: 0x40101)), plan: &plan)
        _ = p.handle(KeyEvent(kind: .flagsChanged, flags: ModifierFlags(rawValue: 0x60103)), plan: &plan)
        _ = p.handle(KeyEvent(kind: .mouseDown), plan: &plan)
        let release = p.handle(KeyEvent(kind: .flagsChanged, flags: ModifierFlags(rawValue: 0x20102)), plan: &plan)
        XCTAssertFalse(release.languageToggled)
        XCTAssertTrue(p.preferences.vietnamese)
    }

    func testFocusHintsOutsideSpotlightOnlyForModifierSpace() {
        var p = makeProcessor()
        XCTAssertTrue(p.handle(keyDown(KeyCode.space, cmd), plan: &plan).focusMayChange)
        XCTAssertTrue(p.handle(keyDown(KeyCode.space, option), plan: &plan).focusMayChange)
        XCTAssertFalse(p.handle(keyDown(KeyCode.space), plan: &plan).focusMayChange)
        // Enter, Esc, click, ⌘C in a regular app do not make FocusProbe query that app over AX
        XCTAssertFalse(p.handle(keyDown(KeyCode.escape), plan: &plan).focusMayChange)
        XCTAssertFalse(p.handle(keyDown(KeyCode.returnKey), plan: &plan).focusMayChange)
        XCTAssertFalse(p.handle(keyDown(8, cmd), plan: &plan).focusMayChange)
        XCTAssertFalse(p.handle(KeyEvent(kind: .mouseDown), plan: &plan).focusMayChange)
        XCTAssertFalse(p.handle(keyDown(0), plan: &plan).focusMayChange)
    }

    func testFocusHintsInsideSpotlight() {
        var p = makeProcessor()
        var ctx = p.context
        ctx.spotlightActive = true
        p.update(context: ctx)
        XCTAssertTrue(p.handle(keyDown(KeyCode.escape), plan: &plan).focusMayChange)
        XCTAssertTrue(p.handle(keyDown(KeyCode.returnKey), plan: &plan).focusMayChange)
        XCTAssertTrue(p.handle(keyDown(KeyCode.enter), plan: &plan).focusMayChange)
        XCTAssertTrue(p.handle(keyDown(18, cmd), plan: &plan).focusMayChange)
        XCTAssertTrue(p.handle(KeyEvent(kind: .mouseDown), plan: &plan).focusMayChange)
        XCTAssertFalse(p.handle(keyDown(0), plan: &plan).focusMayChange)
    }

    // MARK: Spotlight assumption and inline suggestion

    private let second: UInt64 = 1_000_000_000

    private func key(_ code: UInt16, _ flags: ModifierFlags = [], at time: UInt64) -> KeyEvent {
        KeyEvent(kind: .keyDown, keyCode: code, flags: flags, time: time)
    }

    private let withEmptyChar = [emptyChar, backspace, backspace, Step.text("à")]

    /// FocusProbe reports Apple's Spotlight
    private func confirmSpotlight(_ p: inout KeyEventProcessor<FakeEngine>, _ open: Bool = true) {
        var ctx = p.context
        ctx.spotlightActive = open
        ctx.spotlightSuggestions = open
        p.update(context: ctx)
    }

    private func spotlightProcessor() -> KeyEventProcessor<FakeEngine> {
        var p = makeProcessor()
        confirmSpotlight(&p)
        return p
    }

    /// Plan for one engine replacement ("â" over one character)
    private func replaceSteps(_ p: inout KeyEventProcessor<FakeEngine>, at time: UInt64 = 0) -> [Step] {
        engine.nextOutput = replace(1, "â")
        _ = p.handle(key(0, at: time), plan: &plan)
        engine.nextOutput = .init()
        return plan.readable
    }

    private func passKey(_ p: inout KeyEventProcessor<FakeEngine>, _ event: KeyEvent) {
        engine.nextOutput = .init()
        _ = p.handle(event, plan: &plan)
    }

    func testCommandSpaceDropsEmptyCharUntilProbeAnswers() {
        var p = makeProcessor { $0.fixRecommendBrowser = true }
        engine.nextOutput = replace(1, "à")
        _ = p.handle(key(0, at: 10 * second), plan: &plan)
        XCTAssertEqual(plan.readable, withEmptyChar)
        passKey(&p, key(KeyCode.space, cmd, at: 10 * second))
        engine.nextOutput = replace(1, "à")
        _ = p.handle(key(0, at: 10 * second + 50_000_000), plan: &plan)
        // Plain backspaces: no empty char in Spotlight, no Shift+Left (Terminal would get an escape sequence)
        XCTAssertEqual(plan.readable, [backspace, .text("à")])
        // A context push that doesn't report Spotlight (input source change) keeps the assumption
        p.update(context: AppContext(bundleID: "com.apple.TextEdit"))
        _ = p.handle(key(0, at: 10 * second + 100_000_000), plan: &plan)
        XCTAssertEqual(plan.readable, [backspace, .text("à")])
    }

    func testSpotlightAssumptionExpires() {
        var p = makeProcessor { $0.fixRecommendBrowser = true }
        passKey(&p, key(KeyCode.space, cmd, at: 10 * second))
        engine.nextOutput = replace(1, "à")
        _ = p.handle(key(0, at: 11 * second), plan: &plan)
        XCTAssertEqual(plan.readable, withEmptyChar)
    }

    func testSpotlightAssumptionEndsOnEscapeClickOrSecondCommandSpace() {
        for end in [key(KeyCode.escape, at: 10 * second + 1), KeyEvent(kind: .mouseDown),
                    key(KeyCode.space, cmd, at: 10 * second + 1)] {
            var p = makeProcessor { $0.fixRecommendBrowser = true }
            passKey(&p, key(KeyCode.space, cmd, at: 10 * second))
            passKey(&p, end)
            engine.nextOutput = replace(1, "à")
            _ = p.handle(key(0, at: 10 * second + 2), plan: &plan)
            XCTAssertEqual(plan.readable, withEmptyChar, "\(end)")
        }
    }

    func testOnlyPlainCommandSpaceAssumesSpotlight() {
        for flags in [option, ctrl, cmd.union(.shift), none] {
            var p = makeProcessor { $0.fixRecommendBrowser = true }
            passKey(&p, key(KeyCode.space, flags, at: 10 * second))
            engine.nextOutput = replace(1, "à")
            _ = p.handle(key(0, at: 10 * second + 1), plan: &plan)
            XCTAssertEqual(plan.readable, withEmptyChar, "\(flags)")
        }
    }

    func testConfirmedSpotlightClearsInlineSuggestion() {
        var p = makeProcessor()
        passKey(&p, key(KeyCode.space, cmd, at: 10 * second))
        confirmSpotlight(&p)
        XCTAssertEqual(replaceSteps(&p, at: 20 * second), [forwardDelete, shiftLeft, .text("â")])
    }

    func testCaretMovingKeysDisableForwardDelete() {
        let moves = [keyDown(KeyCode.leftArrow), keyDown(126), keyDown(KeyCode.home), keyDown(KeyCode.a, ctrl),
                     keyDown(KeyCode.a, cmd), keyDown(KeyCode.tab), keyDown(KeyCode.escape), keyDown(KeyCode.returnKey),
                     keyDown(KeyCode.rightArrow, [.shift]), keyDown(KeyCode.leftArrow, option), KeyEvent(kind: .mouseDown)]
        for move in moves {
            var p = spotlightProcessor()
            passKey(&p, move)
            XCTAssertEqual(replaceSteps(&p), [shiftLeft, .text("â")], "\(move)")
        }
    }

    func testEndKeysRestoreForwardDelete() {
        for end in [keyDown(KeyCode.end), keyDown(KeyCode.rightArrow, cmd), keyDown(KeyCode.downArrow, cmd)] {
            var p = spotlightProcessor()
            passKey(&p, keyDown(KeyCode.leftArrow))
            passKey(&p, end)
            XCTAssertEqual(replaceSteps(&p), [forwardDelete, shiftLeft, .text("â")], "\(end)")
        }
    }

    func testTypingKeepsForwardDelete() {
        var p = spotlightProcessor()
        for event in [keyDown(KeyCode.a), keyDown(KeyCode.space), keyDown(KeyCode.delete), keyDown(KeyCode.a, [.shift]),
                      keyDown(KeyCode.rightArrow), keyDown(83)] {
            passKey(&p, event)
        }
        XCTAssertEqual(replaceSteps(&p), [forwardDelete, shiftLeft, .text("â")])
    }

    func testCommandSpaceClosingSpotlightDisablesForwardDelete() {
        // FocusProbe still reports Spotlight for a moment after ⌘Space closes it
        var p = spotlightProcessor()
        passKey(&p, key(KeyCode.space, cmd, at: 10 * second))
        XCTAssertEqual(replaceSteps(&p, at: 10 * second + 10_000_000), [shiftLeft, .text("â")])
    }

    func testCaretMoveDuringAssumptionSurvivesConfirmation() {
        var p = makeProcessor()
        passKey(&p, key(KeyCode.space, cmd, at: 10 * second))
        passKey(&p, key(KeyCode.leftArrow, at: 10 * second + 50_000_000))
        confirmSpotlight(&p)
        XCTAssertEqual(replaceSteps(&p, at: 10 * second + 200_000_000), [shiftLeft, .text("â")])
    }

    func testSpotlightOpenedWithoutCommandSpaceIsFreshField() {
        var p = spotlightProcessor()
        passKey(&p, KeyEvent(kind: .mouseDown))
        XCTAssertEqual(replaceSteps(&p), [shiftLeft, .text("â")])
        confirmSpotlight(&p, false)
        confirmSpotlight(&p)
        XCTAssertEqual(replaceSteps(&p), [forwardDelete, shiftLeft, .text("â")])
    }

    func testRaycastWindowUsesSelectionWithoutForwardDelete() {
        // Raycast windows also host notes: never Forward Delete there
        var p = makeProcessor()
        p.update(context: AppContext(bundleID: "com.raycast.macos"))
        XCTAssertEqual(replaceSteps(&p), [shiftLeft, .text("â")])
    }

    func testKeepsCaretAtEnd() {
        for code: UInt16 in [0, 12, 49, 50, KeyCode.delete, 65, 82, 92] {
            XCTAssertTrue(KeyEventProcessor<FakeEngine>.keepsCaretAtEnd(code), "\(code)")
        }
        for code: UInt16 in [KeyCode.returnKey, KeyCode.tab, KeyCode.escape, KeyCode.enter, KeyCode.keypadClear,
                             KeyCode.home, KeyCode.forwardDelete, KeyCode.leftArrow, 122] {
            XCTAssertFalse(KeyEventProcessor<FakeEngine>.keepsCaretAtEnd(code), "\(code)")
        }
    }

    func testEngineReconfiguredOnlyWhenEngineConfigChanges() {
        var p = makeProcessor()
        let count = engine.configs.count
        var prefs = p.preferences
        prefs.beepOnSwitch = true
        prefs.fixChromiumBrowser = true
        p.update(preferences: prefs)
        XCTAssertEqual(engine.configs.count, count)
        prefs.upperCaseFirstChar = true
        p.update(preferences: prefs)
        XCTAssertEqual(engine.configs.count, count + 1)
    }
}

final class SuspendTests: XCTestCase {
    func testSuspendedPassesEverythingIncludingHotkey() {
        let engine = FakeEngine()
        var prefs = Preferences()
        prefs.fixRecommendBrowser = false
        var ctx = AppContext(bundleID: "x")
        ctx.suspended = true
        var p = KeyEventProcessor(engine: engine, preferences: prefs, context: ctx)
        var plan = InjectionPlan()
        _ = p.handle(KeyEvent(kind: .flagsChanged, flags: ModifierFlags(rawValue: 0x80120)), plan: &plan)
        XCTAssertEqual(p.handle(KeyEvent(kind: .keyDown, keyCode: KeyCode.z, flags: ModifierFlags(rawValue: 0x80120)), plan: &plan), .pass)
        XCTAssertTrue(p.preferences.vietnamese)
        XCTAssertTrue(engine.keys.isEmpty)
    }
}

final class EnglishModeMacroTests: XCTestCase {
    private func processor(_ engine: FakeEngine, _ configure: (inout Preferences) -> Void) -> KeyEventProcessor<FakeEngine> {
        var prefs = Preferences()
        prefs.vietnamese = false
        prefs.fixRecommendBrowser = false
        configure(&prefs)
        return KeyEventProcessor(engine: engine, preferences: prefs, context: AppContext(bundleID: "x"))
    }

    func testEnglishModeMacroWhenEnabled() {
        let engine = FakeEngine()
        var p = processor(engine) { $0.useMacroInEnglishMode = true }
        engine.nextEnglishOutput = EngineOutput(action: .macro, backspaces: 3,
                                                characters: "by the way".utf16.map { OutputCharacter(unit: $0) },
                                                restoreKey: OutputCharacter(unit: 0, keyCode: KeyCode.space))
        var plan = InjectionPlan()
        XCTAssertEqual(p.handle(KeyEvent(kind: .keyDown, keyCode: KeyCode.space), plan: &plan), .swallow)
        XCTAssertEqual(engine.englishKeys, [KeyCode.space])
        XCTAssertTrue(engine.keys.isEmpty)
        XCTAssertEqual(plan.readable.last, .key(KeyCode.space, .nonCoalesced))
    }

    func testEnglishModeMacroInSpotlightClearsSuggestion() {
        let engine = FakeEngine()
        var p = processor(engine) { $0.useMacroInEnglishMode = true }
        var ctx = p.context
        ctx.spotlightActive = true
        ctx.spotlightSuggestions = true
        p.update(context: ctx)
        engine.nextEnglishOutput = EngineOutput(action: .macro, backspaces: 2,
                                                characters: "anh".utf16.map { OutputCharacter(unit: $0) },
                                                restoreKey: OutputCharacter(unit: 0, keyCode: KeyCode.space))
        var plan = InjectionPlan()
        _ = p.handle(KeyEvent(kind: .keyDown, keyCode: KeyCode.space), plan: &plan)
        XCTAssertEqual(plan.readable, [forwardDelete, shiftLeft, shiftLeft, .text("anh"), .key(KeyCode.space, .nonCoalesced)])
    }

    func testEnglishModeWithoutOptionPasses() {
        let engine = FakeEngine()
        var p = processor(engine) { _ in }
        var plan = InjectionPlan()
        XCTAssertEqual(p.handle(KeyEvent(kind: .keyDown, keyCode: 0), plan: &plan), .pass)
        XCTAssertTrue(engine.englishKeys.isEmpty)
    }

    func testEnglishModeNeedsUseMacro() {
        let engine = FakeEngine()
        var p = processor(engine) { $0.useMacroInEnglishMode = true; $0.useMacro = false }
        var plan = InjectionPlan()
        _ = p.handle(KeyEvent(kind: .keyDown, keyCode: 0), plan: &plan)
        XCTAssertTrue(engine.englishKeys.isEmpty)
    }

    func testVietnameseModeMacroIsPlanned() {
        // Macros in Vietnamese mode are planned, not passed through
        let engine = FakeEngine()
        var p = processor(engine) { $0.vietnamese = true }
        engine.nextOutput = EngineOutput(action: .macro, backspaces: 2,
                                         characters: "Việt Nam".utf16.map { OutputCharacter(unit: $0) },
                                         restoreKey: OutputCharacter(unit: 0, keyCode: KeyCode.space))
        var plan = InjectionPlan()
        XCTAssertEqual(p.handle(KeyEvent(kind: .keyDown, keyCode: KeyCode.space), plan: &plan), .swallow)
        XCTAssertEqual(plan.readable, [.key(KeyCode.delete, []), .key(KeyCode.delete, []), .text("Việt Nam"),
                                       .key(KeyCode.space, .nonCoalesced)])
    }

    func testMacrosForwardedToEngine() {
        let engine = FakeEngine()
        var p = processor(engine) { _ in }
        p.update(macros: MacroTable(macros: [Macro(text: "a", content: "b")]))
        XCTAssertEqual(engine.macroTables.last?.count, 1)
    }
}
