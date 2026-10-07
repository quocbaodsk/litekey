import XCTest
import LiteKeyEngine
@testable import LiteKeyCore

/// Each test covers one branch of `InjectionPlanner`.
final class InjectionPlannerTests: XCTestCase {
    private var prefs = Preferences()

    /// Any regular app: the autocomplete fix types the empty char in every app except Spotlight
    private static var addressBar: AppContext { AppContext(bundleID: "com.apple.TextEdit") }

    /// Injection steps without sleeps (delays are covered by `testDelays...`)
    private func plan(_ output: EngineOutput, _ context: AppContext = addressBar) -> [Step] {
        planWithDelays(output, context).filter { if case .sleep = $0 { return false } else { return true } }
    }

    private func planWithDelays(_ output: EngineOutput, _ context: AppContext) -> [Step] {
        var plan = InjectionPlan()
        InjectionPlanner.plan(output, context: context, preferences: prefs, into: &plan)
        return plan.readable
    }

    private func app(_ id: String) -> AppContext {
        AppContext(bundleID: id, rules: .builtIn, preferences: prefs)
    }

    func testPassProducesNothing() {
        XCTAssertEqual(plan(EngineOutput()), [])
    }

    // MARK: Autocomplete fix (empty char)

    func testEmptyCharBeforeBackspaces() {
        XCTAssertEqual(plan(replace(1, "â")), [emptyChar, backspace, backspace, .text("â")])
    }

    func testEmptyCharEvenWithoutBackspace() {
        // The empty char is typed and deleted even when the engine needs no backspaces
        XCTAssertEqual(plan(replace(0, "A")), [emptyChar, backspace, .text("A")])
    }

    func testExtCode4WithoutBackspaceSkipsEmptyChar() {
        XCTAssertEqual(plan(replace(0, "ư", noEmpty: true)), [.text("ư")])
    }

    func testExtCode4WithBackspacesSkipsEmptyChar() {
        // `noEmptyCharPrefix` skips the empty char, with or without backspaces
        XCTAssertEqual(plan(replace(2, "ươ", noEmpty: true)), [backspace, backspace, .text("ươ")])
    }

    func testSublimeUsesU200C() {
        XCTAssertEqual(plan(replace(1, "â"), app("com.sublimetext.3")), [niceSpace, backspace, backspace, .text("â")])
    }

    func testEmptyCharInEveryApp() {
        // Applies to every app, regardless of the focused field
        for id in ["com.apple.TextEdit", "com.tinyspeck.slackmacgap", "com.google.Chrome", "com.microsoft.VSCode",
                   "com.apple.Safari"] {
            XCTAssertEqual(plan(replace(1, "à"), app(id)), [emptyChar, backspace, backspace, .text("à")], id)
        }
    }

    func testFixRecommendOff() {
        prefs.fixRecommendBrowser = false
        XCTAssertEqual(plan(replace(1, "â")), [backspace, .text("â")])
    }

    // MARK: Chromium fix (Shift+Left)

    func testChromiumFixSingleBackspaceBecomesSelection() {
        prefs.fixChromiumBrowser = true
        XCTAssertEqual(plan(replace(1, "â"), app("com.google.Chrome")), [shiftLeft, .text("â")])
    }

    func testChromiumFixManyBackspaces() {
        prefs.fixChromiumBrowser = true
        XCTAssertEqual(plan(replace(3, "ười"), app("com.google.Chrome")),
                       [shiftLeft, backspace, backspace, backspace, .text("ười")])
    }

    func testChromiumFixWithoutBackspace() {
        prefs.fixChromiumBrowser = true
        XCTAssertEqual(plan(replace(0, "A"), app("com.brave.Browser")), [.text("A")])
    }

    func testChromiumFixOnlyForListedApps() {
        prefs.fixChromiumBrowser = true
        // Firefox is not Chromium: it keeps the empty char
        XCTAssertEqual(plan(replace(1, "â"), app("org.mozilla.firefox")), [emptyChar, backspace, backspace, .text("â")])
        // Stable Edge is `com.microsoft.edgemac`
        XCTAssertEqual(plan(replace(1, "â"), app("com.microsoft.edgemac")), [shiftLeft, .text("â")])
    }

    func testChromiumFixNeedsFixRecommend() {
        prefs.fixChromiumBrowser = true
        prefs.fixRecommendBrowser = false
        XCTAssertEqual(plan(replace(1, "â"), app("com.google.Chrome")), [backspace, .text("â")])
    }

    // MARK: Spotlight (selection)

    func testSpotlightUsesSelection() {
        var ctx = app("com.apple.finder")
        ctx.spotlightActive = true
        XCTAssertEqual(plan(replace(2, "ấy"), ctx), [shiftLeft, shiftLeft, .text("ấy")])
    }

    func testSpotlightBundleUsesSelection() {
        XCTAssertEqual(plan(replace(1, "â"), app(AppRules.spotlight)), [shiftLeft, .text("â")])
    }

    func testSpotlightWithoutBackspace() {
        var ctx = app("com.apple.finder")
        ctx.spotlightActive = true
        XCTAssertEqual(plan(replace(0, "A"), ctx), [.text("A")])
    }

    func testSpotlightClearsInlineSuggestionFirst() {
        var ctx = app("com.apple.finder")
        ctx.spotlightActive = true
        var p = InjectionPlan()
        InjectionPlanner.plan(replace(1, "à"), context: ctx, preferences: prefs, clearInlineSuggestion: true, into: &p)
        XCTAssertEqual(p.readable, [forwardDelete, shiftLeft, .text("à")])
    }

    func testSpotlightWithoutBackspaceNeverClears() {
        // Typed text replaces a selected suggestion on its own
        var ctx = app("com.apple.finder")
        ctx.spotlightActive = true
        var p = InjectionPlan()
        InjectionPlanner.plan(replace(0, "ư"), context: ctx, preferences: prefs, clearInlineSuggestion: true, into: &p)
        XCTAssertEqual(p.readable, [.text("ư")])
    }

    func testClearInlineSuggestionIgnoredOutsideSpotlight() {
        prefs.fixRecommendBrowser = false
        var p = InjectionPlan()
        InjectionPlanner.plan(replace(1, "â"), context: app("com.apple.TextEdit"), preferences: prefs,
                              clearInlineSuggestion: true, into: &p)
        XCTAssertEqual(p.readable, [backspace, .text("â")])
    }

    func testOverlayLaunchersUseSelection() {
        for id in ["com.raycast.macos", "com.runningwithcrayons.Alfred"] {
            XCTAssertEqual(plan(replace(1, "â"), app(id)), [shiftLeft, .text("â")], id)
        }
    }

    // MARK: Backspaces

    func testTooManyBackspacesAreSkipped() {
        prefs.fixRecommendBrowser = false
        XCTAssertEqual(plan(replace(32, "a")), [.text("a")])
        XCTAssertEqual(plan(replace(31, "a")).filter { $0 == backspace }.count, 31)
    }

    func testEmptyCharCountsTowardBackspaceLimit() {
        // 31 + 1 for the empty char = 32: no backspaces
        XCTAssertEqual(plan(replace(31, "a")), [emptyChar, .text("a")])
    }

    private func settle(_ output: EngineOutput, _ context: AppContext) -> UInt32 {
        var plan = InjectionPlan()
        InjectionPlanner.plan(output, context: context, preferences: prefs, into: &plan)
        return plan.settle
    }

    func testDelaysSlowApp() {
        // Settle is not a trailing sleep step; `SettleGate` waits only if the next real key arrives early
        XCTAssertEqual(planWithDelays(replace(1, "ê"), app("com.jetbrains.goland")),
                       [emptyChar, .sleep(3000), backspace, .sleep(3000), backspace, .sleep(3000), .sleep(6000), .text("ê")])
        XCTAssertEqual(settle(replace(1, "ê"), app("com.apple.Terminal")), 20000)
    }

    func testTerminalsSkipAutocompleteFix() {
        // No inline autocomplete in terminals: one backspace and 9 ms of pauses instead of 3 and 15 ms
        for id in AppRules.terminalApps {
            XCTAssertEqual(planWithDelays(replace(1, "ê"), app(id)), [backspace, .sleep(3000), .sleep(6000), .text("ê")], id)
        }
        // The empty char is still typed for slow apps with completions
        for id in ["com.google.android.studio", "dev.warp.Warp-Stable"] {
            XCTAssertEqual(plan(replace(1, "ê"), app(id)).first, emptyChar, id)
            XCTAssertEqual(app(id).rule.delays, .slow, id)
        }
    }

    func testNoDelaysByDefault() {
        // Sent in one go: no sleeps in the callback, no wait before the next key
        XCTAssertEqual(planWithDelays(replace(1, "â"), app("com.google.Chrome")),
                       [emptyChar, backspace, backspace, .text("â")])
        for id in ["com.apple.TextEdit", "com.tinyspeck.slackmacgap", "com.apple.Safari", AppRules.spotlight] {
            XCTAssertEqual(planWithDelays(replace(1, "â"), app(id)).filter {
                if case .sleep = $0 { return true } else { return false }
            }, [], id)
            XCTAssertEqual(settle(replace(1, "â"), app(id)), 0, id)
        }
    }

    func testDelaysBetweenTextChunks() {
        prefs.fixRecommendBrowser = false
        let long = String(repeating: "a", count: 20)
        XCTAssertEqual(planWithDelays(replace(0, long), app("com.apple.Terminal")),
                       [.text(String(repeating: "a", count: 16)), .sleep(3000), .text("aaaa")])
    }

    func testDelaysBeforeResentKey() {
        prefs.fixRecommendBrowser = false
        let out = restore(1, keys: [(8, "c")], restore: OutputCharacter(unit: 0, keyCode: KeyCode.tab))
        XCTAssertEqual(planWithDelays(out, app("com.apple.Terminal")),
                       [backspace, .sleep(3000), .sleep(6000), .text("c"), .sleep(3000), .repost])
    }

    func testSettleIsResetWithPlan() {
        var p = InjectionPlan()
        InjectionPlanner.plan(replace(1, "ê"), context: app("com.apple.Terminal"), preferences: prefs, into: &p)
        XCTAssertEqual(p.settle, 20000)
        InjectionPlanner.plan(replace(1, "ê"), context: app("com.apple.TextEdit"), preferences: prefs, into: &p)
        XCTAssertEqual(p.settle, 0)
    }

    func testNoDelaysWithStandardRule() {
        XCTAssertEqual(planWithDelays(replace(1, "â"), Self.addressBar),
                       [emptyChar, backspace, backspace, .text("â")])
    }

    // MARK: New text

    func testLongTextIsChunkedBy16() {
        prefs.fixRecommendBrowser = false
        let long = String(repeating: "a", count: 20)
        XCTAssertEqual(plan(replace(0, long)), [.text(String(repeating: "a", count: 16)), .text("aaaa")])
    }

    func testRestoreAppendsKeyCharacter() {
        prefs.fixRecommendBrowser = false
        let out = restore(2, keys: [(8, "c"), (0, "a")], restore: OutputCharacter(unit: 0x73, keyCode: 1))
        XCTAssertEqual(plan(out), [backspace, backspace, .text("cas")])
    }

    func testRestoreWithControlKeyResendsOriginal() {
        prefs.fixRecommendBrowser = false
        let out = restore(2, keys: [(8, "c"), (0, "a")], restore: OutputCharacter(unit: 0, keyCode: KeyCode.tab))
        XCTAssertEqual(plan(out), [backspace, backspace, .text("ca"), .repost])
    }

    // MARK: Send key by key

    func testStepByStepSendsKeyCodesAndUnicode() {
        prefs.fixRecommendBrowser = false
        prefs.sendKeyStepByStep = true
        let out = EngineOutput(action: .replace, backspaces: 1, characters: [
            OutputCharacter(unit: 0x54, keyCode: 17, shifted: true),   // T
            OutputCharacter(unit: 0x1EBF),                             // ế
        ])
        XCTAssertEqual(plan(out), [backspace, .key(17, [.shift, .nonCoalesced]), .text("ế")])
    }

    func testStepByStepRestore() {
        prefs.fixRecommendBrowser = false
        prefs.sendKeyStepByStep = true
        let out = restore(1, keys: [(8, "c")], restore: OutputCharacter(unit: 0x53, keyCode: 1, shifted: true))
        XCTAssertEqual(plan(out), [backspace, .key(8, .nonCoalesced), .key(1, [.shift, .nonCoalesced])])
        let tab = restore(1, keys: [(8, "c")], restore: OutputCharacter(unit: 0, keyCode: KeyCode.tab))
        XCTAssertEqual(plan(tab), [backspace, .key(8, .nonCoalesced), .repost])
    }

    func testPlanReuseKeepsNoStaleSteps() {
        var p = InjectionPlan()
        let ctx = AppContext()
        InjectionPlanner.plan(replace(3, "abc"), context: ctx, preferences: prefs, into: &p)
        prefs.fixRecommendBrowser = false
        InjectionPlanner.plan(replace(0, "d"), context: ctx, preferences: prefs, into: &p)
        XCTAssertEqual(p.readable, [.text("d")])
        XCTAssertEqual(p.text, Array("d".utf16))
    }
}

final class InjectionPlanChunkTests: XCTestCase {
    func testEmojiNeverSplitAcrossEvents() {
        // 15 letters + 😀 (two UTF-16 units) straddles the 16-unit boundary
        let text = String(repeating: "a", count: 15) + "😀b"
        for build in [{ (p: inout InjectionPlan) in p.type(text.utf16) },
                      { (p: inout InjectionPlan) in text.utf16.forEach { p.append($0) }; p.flushText() }] {
            var p = InjectionPlan()
            build(&p)
            XCTAssertEqual(p.readable, [.text(String(repeating: "a", count: 15)), .text("😀b")])
        }
    }

    func testFullChunkEndingInEmojiStaysWhole() {
        var p = InjectionPlan()
        p.type((String(repeating: "a", count: 14) + "😀").utf16)
        XCTAssertEqual(p.readable, [.text(String(repeating: "a", count: 14) + "😀")])
    }
}

/// Macro expansion branch
final class MacroPlannerTests: XCTestCase {
    private func macro(_ bs: Int, _ text: String, trigger: UInt16 = KeyCode.space, shift: Bool = false) -> EngineOutput {
        EngineOutput(action: .macro, backspaces: bs, characters: text.utf16.map { OutputCharacter(unit: $0) },
                     restoreKey: OutputCharacter(unit: 0, keyCode: trigger, shifted: shift))
    }

    private func plan(_ output: EngineOutput, _ prefs: Preferences = Preferences(), _ ctx: AppContext = AppContext(bundleID: "x"),
                      clear: Bool = false) -> [Step] {
        var plan = InjectionPlan()
        InjectionPlanner.plan(output, context: ctx, preferences: prefs, clearInlineSuggestion: clear, into: &plan)
        return plan.readable.filter { if case .sleep = $0 { return false } else { return true } }
    }

    func testMacroDelays() {
        let ctx = AppContext(bundleID: "com.jetbrains.goland", rules: .builtIn, preferences: Preferences())
        var plan = InjectionPlan()
        InjectionPlanner.plan(macro(1, "anh"), context: ctx, preferences: Preferences(), into: &plan)
        XCTAssertEqual(plan.readable, [emptyChar, .sleep(3000), backspace, .sleep(3000), backspace, .sleep(3000), .sleep(6000),
                                       .text("anh"), .sleep(3000), .key(KeyCode.space, .nonCoalesced)])
        XCTAssertEqual(plan.settle, 20000)
        let terminal = AppContext(bundleID: "com.apple.Terminal", rules: .builtIn, preferences: Preferences())
        InjectionPlanner.plan(macro(1, "anh"), context: terminal, preferences: Preferences(), into: &plan)
        XCTAssertEqual(plan.readable, [backspace, .sleep(3000), .sleep(6000), .text("anh"), .sleep(3000),
                                       .key(KeyCode.space, .nonCoalesced)])
    }

    func testMacroNoDelaysInBrowser() {
        let ctx = AppContext(bundleID: "com.google.Chrome", rules: .builtIn, preferences: Preferences())
        var plan = InjectionPlan()
        InjectionPlanner.plan(macro(1, "anh"), context: ctx, preferences: Preferences(), into: &plan)
        XCTAssertEqual(plan.readable, [emptyChar, backspace, backspace, .text("anh"), .key(KeyCode.space, .nonCoalesced)])
        XCTAssertEqual(plan.settle, 0)
    }

    func testMacroWithoutBackspaceStillSendsEmptyChar() {
        XCTAssertEqual(plan(macro(0, "anh")), [emptyChar, backspace, .text("anh"), .key(KeyCode.space, .nonCoalesced)])
    }

    func testMacroWithEmptyChar() {
        XCTAssertEqual(plan(macro(2, "Việt Nam")),
                       [emptyChar, backspace, backspace, backspace, .text("Việt Nam"), .key(KeyCode.space, .nonCoalesced)])
    }

    func testMacroWithoutFixRecommend() {
        var prefs = Preferences()
        prefs.fixRecommendBrowser = false
        XCTAssertEqual(plan(macro(3, "by the way", trigger: 47, shift: true), prefs),
                       [backspace, backspace, backspace, .text("by the way"), .key(47, [.shift, .nonCoalesced])])
    }

    func testMacroIgnoresBackspaceLimitAndChromiumFix() {
        var prefs = Preferences()
        prefs.fixChromiumBrowser = true
        let ctx = AppContext(bundleID: "com.google.Chrome", rules: .builtIn, preferences: prefs)
        let steps = plan(macro(40, "x"), prefs, ctx)
        XCTAssertEqual(steps.first, emptyChar)
        XCTAssertEqual(steps.filter { $0 == backspace }.count, 41)
    }

    func testMacroInSpotlightUsesSelection() {
        // A backspace would only remove Spotlight's inline suggestion and leave part of the shortcut
        var ctx = AppContext(bundleID: "x")
        ctx.spotlightActive = true
        XCTAssertEqual(plan(macro(2, "anh"), Preferences(), ctx),
                       [shiftLeft, shiftLeft, .text("anh"), .key(KeyCode.space, .nonCoalesced)])
    }

    func testMacroInSpotlightClearsSuggestionAndIgnoresBackspaceLimit() {
        var ctx = AppContext(bundleID: "x")
        ctx.spotlightActive = true
        let steps = plan(macro(40, "x"), Preferences(), ctx, clear: true)
        XCTAssertEqual(steps.first, forwardDelete)
        XCTAssertEqual(steps.filter { $0 == shiftLeft }.count, 40)
        XCTAssertFalse(steps.contains(backspace))
    }

    func testMacroStepByStep() {
        var prefs = Preferences()
        prefs.fixRecommendBrowser = false
        prefs.sendKeyStepByStep = true
        let out = EngineOutput(action: .macro, backspaces: 1, characters: [
            OutputCharacter(unit: 0x61, keyCode: 0), OutputCharacter(unit: 0x1EA1),
        ], restoreKey: OutputCharacter(unit: 0, keyCode: KeyCode.space))
        XCTAssertEqual(plan(out, prefs), [backspace, .key(0, .nonCoalesced), .text("ạ"), .key(KeyCode.space, .nonCoalesced)])
    }
}
