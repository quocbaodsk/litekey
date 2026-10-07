import Foundation
import XCTest
@testable import LiteKeyCore

final class PreferencesTests: XCTestCase {
    func testRoundTrip() throws {
        var p = Preferences()
        p.inputType = .vni
        p.hotkey = .controlSpace
        p.excludedApps = ["a.b"]
        let data = try JSONEncoder().encode(p)
        XCTAssertEqual(try JSONDecoder().decode(Preferences.self, from: data), p)
    }

    func testTogglingExcluded() {
        var p = Preferences()
        p.excludedApps = ["a.b"]
        p = p.togglingExcluded("c.d")
        XCTAssertEqual(p.excludedApps, ["a.b", "c.d"])
        XCTAssertTrue(p.isExcluded("c.d"))
        p = p.togglingExcluded("a.b")
        XCTAssertEqual(p.excludedApps, ["c.d"])
        XCTAssertFalse(p.isExcluded("a.b"))
        // Toggling twice restores the list; other settings are untouched
        let before = Preferences()
        XCTAssertEqual(before.togglingExcluded("x.y").togglingExcluded("x.y"), before)
    }

    func testMissingKeysUseDefaults() throws {
        let p = try JSONDecoder().decode(Preferences.self, from: Data(#"{"version":3,"inputType":1}"#.utf8))
        var expected = Preferences()
        expected.inputType = .vni
        XCTAssertEqual(p, expected)
    }

    func testInvalidValueFallsBackToDefault() throws {
        let p = try JSONDecoder().decode(Preferences.self, from: Data(#"{"inputType":9,"checkSpelling":false}"#.utf8))
        XCTAssertEqual(p.inputType, .telex)
        XCTAssertFalse(p.checkSpelling)
    }

    func testDefaults() {
        let p = Preferences()
        XCTAssertTrue(p.vietnamese)
        XCTAssertEqual(p.inputType, .telex)
        // Default hotkey is ⌃⇧
        XCTAssertEqual(p.hotkey, .controlShift)
        XCTAssertFalse(p.beepOnSwitch)
        XCTAssertTrue(p.checkSpelling)
        XCTAssertFalse(p.modernOrthography)
        XCTAssertFalse(p.quickTelex)
        XCTAssertTrue(p.rememberPerApp)
        XCTAssertTrue(p.disableOnNonEnglishInputSource)
        XCTAssertTrue(p.fixRecommendBrowser)
        // The control panel shows on first launch
        XCTAssertTrue(p.showPanelOnStartup)
        XCTAssertFalse(p.fixChromiumBrowser)
        XCTAssertFalse(p.sendKeyStepByStep)
        XCTAssertTrue(p.fixOverlayLauncher)
        XCTAssertFalse(p.layoutCompatibility)
        XCTAssertEqual(p.excludedApps, [])
        XCTAssertTrue(p.useMacro)
        XCTAssertFalse(p.useMacroInEnglishMode)
        XCTAssertFalse(p.autoCapsMacro)
        // Restoring invalid words is on by default
        XCTAssertTrue(p.restoreIfWrong)
    }

    func testFixOverlayLauncherDecoding() throws {
        // Settings saved before the option existed get it on
        let old = try JSONDecoder().decode(Preferences.self, from: Data(#"{"version":3}"#.utf8))
        XCTAssertTrue(old.fixOverlayLauncher)
        var p = Preferences()
        p.fixOverlayLauncher = false
        let decoded = try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(p))
        XCTAssertFalse(decoded.fixOverlayLauncher)
    }

    func testV1ConfigMigratesHotkey() throws {
        let json = #"{"hotkey":{"modifiers":393216},"inputType":1}"#
        let p = try JSONDecoder().decode(Preferences.self, from: Data(json.utf8))
        XCTAssertEqual(p.version, 1)
        XCTAssertEqual(p.hotkey, .controlShift)
        let m = p.migrated()
        XCTAssertEqual(m.hotkey, .controlShift)
        XCTAssertEqual(m.inputType, .vni)
        XCTAssertEqual(m.version, Preferences.currentVersion)
    }

    func testVersion2DefaultHotkeyMigratesToControlShift() throws {
        // v2 settings on ⌥Z (the old default) → ⌃⇧; other hotkeys are kept
        let json = #"{"version":2,"hotkey":{"modifiers":524288,"keyCode":6}}"#
        let p = try JSONDecoder().decode(Preferences.self, from: Data(json.utf8))
        XCTAssertEqual(p.hotkey, .optionZ)
        XCTAssertEqual(p.migrated().hotkey, .controlShift)
        var space = Preferences()
        space.version = 2
        space.hotkey = .controlSpace
        XCTAssertEqual(space.migrated().hotkey, .controlSpace)
    }

    func testCurrentVersionKeepsOptionZ() throws {
        var p = Preferences()
        p.hotkey = .optionZ
        let decoded = try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(p))
        XCTAssertEqual(decoded.migrated().hotkey, .optionZ)
    }

    func testCurrentVersionKeepsChosenHotkey() throws {
        var p = Preferences()
        p.hotkey = .controlShift
        let decoded = try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(p))
        XCTAssertEqual(decoded.migrated().hotkey, .controlShift)
    }

    func testEngineConfig() {
        var p = Preferences()
        p.modernOrthography = true
        p.checkSpelling = false
        XCTAssertTrue(p.engineConfig.modernOrthography)
        XCTAssertFalse(p.engineConfig.checkSpelling)
    }
}

final class AppRulesTests: XCTestCase {
    func testBuiltInStyles() {
        let rules = AppRules.builtIn
        // Default: no delays
        XCTAssertEqual(rules.rule(for: nil), AppRule())
        XCTAssertEqual(rules.rule(for: "com.apple.TextEdit"), AppRule())
        XCTAssertEqual(rules.rule(for: "com.sublimetext.3").emptyChar, 0x200C)
        XCTAssertTrue(rules.rule(for: "com.google.Chrome").chromiumFix)
        XCTAssertFalse(rules.rule(for: "com.apple.Safari").chromiumFix)
        XCTAssertEqual(rules.rule(for: "com.apple.Terminal").delays, .slow)
        XCTAssertEqual(rules.rule(for: "com.jetbrains.goland").delays, .slow)
        for id in ["com.raphaelamorim.rio", "com.termius-dmg.mac", "com.cmuxterm.app"] {
            XCTAssertEqual(rules.rule(for: id).delays, .slow, id)
        }
        XCTAssertEqual(rules.rule(for: "com.google.Chrome").delays, .none)
        XCTAssertEqual(rules.rule(for: "com.sublimetext.3").delays, .none)
    }

    func testChromiumFixCoversStableEdgeAndOtherChromiumBrowsers() {
        let rules = AppRules.builtIn
        for id in ["com.microsoft.edgemac", "company.thebrowser.Browser", "com.vivaldi.Vivaldi",
                   "com.operasoftware.Opera", "org.chromium.Chromium", "com.google.Chrome.canary"] {
            XCTAssertTrue(rules.rule(for: id).chromiumFix, id)
        }
        XCTAssertFalse(rules.rule(for: "org.mozilla.firefox").chromiumFix)
    }

    func testPassThroughAppsIgnoreCase() {
        let rules = AppRules.builtIn
        XCTAssertTrue(rules.rule(for: "com.microsoft.rdc.macos").passThrough)
        XCTAssertTrue(rules.rule(for: "com.teamviewer.TeamViewer").passThrough)
        XCTAssertTrue(rules.rule(for: "com.apple.iphonesimulator").passThrough)
        XCTAssertFalse(rules.rule(for: "com.apple.TextEdit").passThrough)
        XCTAssertFalse(rules.rule(for: nil).passThrough)
    }

    func testAlwaysEnglish() {
        var prefs = Preferences()
        prefs.excludedApps = ["com.apple.TextEdit"]
        let rules = AppRules.builtIn
        XCTAssertTrue(rules.alwaysEnglish("com.apple.TextEdit", preferences: prefs))
        XCTAssertTrue(rules.alwaysEnglish("com.vmware.fusion", preferences: prefs))
        XCTAssertFalse(rules.alwaysEnglish("com.apple.Notes", preferences: prefs))
        XCTAssertFalse(rules.alwaysEnglish(nil, preferences: prefs))
    }

    func testPassThroughAppContextIsExcluded() {
        let ctx = AppContext(bundleID: "com.p5sys.jump.mac.viewer", rules: .builtIn, preferences: Preferences())
        XCTAssertTrue(ctx.isExcluded)
    }

    func testOverlayWithFocusIsNeverExcluded() {
        var prefs = Preferences()
        prefs.excludedApps = ["com.apple.Terminal"]
        var ctx = AppContext(bundleID: "com.apple.Terminal", rules: .builtIn, preferences: prefs)
        XCTAssertTrue(ctx.excluded(by: prefs))
        ctx.spotlightActive = true
        ctx.overlayBundleID = AppRules.spotlight
        XCTAssertFalse(ctx.excluded(by: prefs))
    }

    func testExcludedOverlayLauncherStaysExcluded() {
        var prefs = Preferences()
        prefs.excludedApps = ["com.raycast.macos"]
        var ctx = AppContext(bundleID: "com.apple.TextEdit", rules: .builtIn, preferences: prefs)
        XCTAssertFalse(ctx.isExcluded)
        ctx.spotlightActive = true
        ctx.overlayBundleID = "com.raycast.macos"
        XCTAssertTrue(ctx.excluded(by: prefs))
    }

    func testContextFromRules() {
        var prefs = Preferences()
        prefs.excludedApps = ["com.apple.Terminal"]
        let ctx = AppContext(bundleID: "com.apple.Terminal", rules: .builtIn, preferences: prefs)
        XCTAssertEqual(ctx, AppContext(bundleID: "com.apple.Terminal", rule: AppRule(autocompleteFix: false, delays: .slow),
                                       isExcluded: true))
        XCTAssertFalse(ctx.isSpotlight)
        XCTAssertTrue(AppContext(bundleID: AppRules.spotlight).isSpotlight)
    }
}

final class PerAppLanguageStoreTests: XCTestCase {
    func testFirstActivationRemembersCurrent() {
        var s = PerAppLanguageStore()
        XCTAssertNil(s.activate("a", current: true))
        XCTAssertEqual(s.language(for: "a"), true)
    }

    func testActivationRestoresRemembered() {
        var s = PerAppLanguageStore()
        s.remember(false, for: "a")
        XCTAssertEqual(s.activate("a", current: true), false)
        XCTAssertNil(s.activate("a", current: false))
    }

    func testExcludedAppNeitherSwitchesNorRecords() {
        var s = PerAppLanguageStore(languages: ["a": false])
        XCTAssertNil(s.activate("a", current: true, excluded: true))
        XCTAssertNil(s.activate("b", current: true, excluded: true))
        XCTAssertNil(s.language(for: "b"))
    }

    func testRememberIgnoresNil() {
        var s = PerAppLanguageStore()
        s.remember(true, for: nil)
        XCTAssertTrue(s.languages.isEmpty)
    }

    func testForgetAll() {
        var s = PerAppLanguageStore(languages: ["a": true])
        s.forgetAll()
        XCTAssertNil(s.language(for: "a"))
    }
}
