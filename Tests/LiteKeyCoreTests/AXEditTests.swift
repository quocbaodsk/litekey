import XCTest
import LiteKeyEngine
@testable import LiteKeyCore

/// Experimental AX edit: which apps and replacements get `plan.axEdit`, and the range it replaces.
final class AXEditTests: XCTestCase {
    private var prefs = Preferences()

    /// Apple's Spotlight field confirmed by FocusProbe over another app
    private static var spotlight: AppContext {
        var ctx = AppContext(bundleID: "com.apple.finder", rules: .builtIn, preferences: Preferences())
        ctx.spotlightActive = true
        ctx.overlayBundleID = AppRules.spotlight
        ctx.overlayAXEdit = AppRules.builtIn.rule(for: AppRules.spotlight).axEdit
        return ctx
    }

    private func plan(_ output: EngineOutput, _ context: AppContext = spotlight, clear: Bool = false) -> InjectionPlan {
        var plan = InjectionPlan()
        InjectionPlanner.plan(output, context: context, preferences: prefs, clearInlineSuggestion: clear, into: &plan)
        return plan
    }

    private func axText(_ plan: InjectionPlan) -> String? {
        guard let edit = plan.axEdit else { return nil }
        return String(decoding: plan.text[edit.textStart ..< edit.textStart + edit.textCount], as: UTF16.self)
    }

    // MARK: Which apps

    func testOnlyOverlayLaunchersGetAXEdit() {
        for id in [AppRules.spotlight, "com.raycast.macos", "com.runningwithcrayons.Alfred"] {
            XCTAssertTrue(AppRules.builtIn.rule(for: id).axEdit, id)
        }
        for id in ["com.apple.TextEdit", "com.google.Chrome", "com.microsoft.VSCode", "com.apple.Terminal",
                   "com.jetbrains.goland"] {
            XCTAssertFalse(AppRules.builtIn.rule(for: id).axEdit, id)
        }
    }

    func testOverlayRuleDecidesWhileLauncherIsOpen() {
        XCTAssertTrue(Self.spotlight.axEdit)
        // Overlay not listed (unknown launcher): key events
        var unlisted = Self.spotlight
        unlisted.overlayBundleID = "com.example.launcher"
        unlisted.overlayAXEdit = AppRules.builtIn.rule(for: "com.example.launcher").axEdit
        XCTAssertFalse(unlisted.axEdit)
        // Launcher closed: the app's own rule
        var closed = Self.spotlight
        closed.spotlightActive = false
        XCTAssertFalse(closed.axEdit)
    }

    func testRaycastAsFrontAppGetsAXEdit() {
        // Raycast's own windows (notes) are the front app, not an overlay
        let raycast = AppContext(bundleID: "com.raycast.macos", rules: .builtIn, preferences: prefs)
        XCTAssertEqual(plan(replace(1, "â"), raycast).axEdit?.deleting, 1)
    }

    func testRegularAppGetsNoAXEdit() {
        let textEdit = AppContext(bundleID: "com.apple.TextEdit", rules: .builtIn, preferences: prefs)
        XCTAssertNil(plan(replace(2, "ấy"), textEdit).axEdit)
    }

    // MARK: Planning

    func testSpotlightReplacementKeepsKeyEventsAsFallback() {
        let p = plan(replace(2, "ấy"), clear: true)
        XCTAssertEqual(p.axEdit?.deleting, 2)
        XCTAssertEqual(axText(p), "ấy")
        // The fallback is the usual Spotlight plan, in full
        XCTAssertEqual(p.axEdit?.fallbackEnd, p.steps.count)
        XCTAssertEqual(p.readable, [forwardDelete, shiftLeft, shiftLeft, .text("ấy")])
    }

    func testDeletionOnlyReplacement() {
        let p = plan(EngineOutput(action: .replace, backspaces: 1))
        XCTAssertEqual(p.axEdit?.deleting, 1)
        XCTAssertEqual(p.axEdit?.textCount, 0)
    }

    func testRestoredWordIncludesRestoreKeyAndRepostsAfter() {
        // Invalid word ended by a control key: the key is reposted after either path
        let out = restore(2, keys: [(0, "a"), (1, "s")], restore: OutputCharacter(unit: 0, keyCode: KeyCode.returnKey))
        let p = plan(out)
        XCTAssertEqual(axText(p), "as")
        XCTAssertEqual(p.readable[p.axEdit!.fallbackEnd...].last, .repost)
        XCTAssertFalse(p.readable[..<p.axEdit!.fallbackEnd].contains(.repost))
    }

    func testRestoreCharacterIsPartOfText() {
        let out = restore(1, keys: [(0, "a")], restore: OutputCharacter(unit: 0x73, keyCode: 1))
        XCTAssertEqual(axText(plan(out)), "as")
    }

    func testNoAXEditWithoutBackspaces() {
        // A plain insert already replaces Spotlight's selected suggestion
        XCTAssertNil(plan(replace(0, "ư")).axEdit)
    }

    func testNoAXEditAtBackspaceLimit() {
        XCTAssertNil(plan(replace(InjectionPlanner.maxBackspaces, "a")).axEdit)
        XCTAssertNotNil(plan(replace(InjectionPlanner.maxBackspaces - 1, "a")).axEdit)
    }

    func testNoAXEditKeyByKey() {
        prefs.sendKeyStepByStep = true
        XCTAssertNil(plan(replace(1, "â")).axEdit)
    }

    func testNoAXEditForMacros() {
        let out = EngineOutput(action: .macro, backspaces: 2, characters: [OutputCharacter(unit: 0x61)],
                               restoreKey: OutputCharacter(unit: 0, keyCode: KeyCode.space))
        XCTAssertNil(plan(out).axEdit)
    }

    func testResetClearsAXEdit() {
        var p = plan(replace(1, "â"))
        XCTAssertNotNil(p.axEdit)
        p.reset()
        XCTAssertNil(p.axEdit)
    }

    // MARK: Replace range

    func testRangeCoversWordBeforeCaret() {
        let r = AXEdit.replaceRange(caret: 5, selection: 0, total: 5, deleting: 2)
        XCTAssertEqual(r?.location, 3)
        XCTAssertEqual(r?.length, 2)
    }

    func testRangeIncludesSelectedSuggestion() {
        // "ma|il" with "il" auto-selected: replace "a" and the suggestion together
        let r = AXEdit.replaceRange(caret: 2, selection: 2, total: 4, deleting: 1)
        XCTAssertEqual(r?.location, 1)
        XCTAssertEqual(r?.length, 3)
    }

    func testRangeWithoutCharacterCount() {
        XCTAssertEqual(AXEdit.replaceRange(caret: 3, selection: 0, total: nil, deleting: 3)?.location, 0)
    }

    func testRangeRejectsFieldWithoutOurWord() {
        // Fewer characters before the caret than we typed
        XCTAssertNil(AXEdit.replaceRange(caret: 1, selection: 0, total: 1, deleting: 2))
    }

    func testRangeRejectsInconsistentNumbers() {
        XCTAssertNil(AXEdit.replaceRange(caret: 4, selection: 2, total: 5, deleting: 1))
        XCTAssertNil(AXEdit.replaceRange(caret: 4, selection: -1, total: 5, deleting: 1))
        XCTAssertNil(AXEdit.replaceRange(caret: 4, selection: 0, total: 5, deleting: 0))
    }
}
