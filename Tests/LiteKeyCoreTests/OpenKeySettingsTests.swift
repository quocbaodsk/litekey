import XCTest
@testable import LiteKeyCore

final class OpenKeySettingsTests: XCTestCase {
    func testDefaultSwitchKeyIsOptionZ() {
        // OpenKey's default switch key status
        let decoded = OpenKeySettings.decodeSwitchKey(0x7A000206)
        XCTAssertEqual(decoded.hotkey, .optionZ)
        XCTAssertFalse(decoded.beep)
    }

    func testModifierOnlySwitchKeyWithBeep() {
        let decoded = OpenKeySettings.decodeSwitchKey(0x8000 | 0x800 | 0x100 | 0xFE)
        XCTAssertEqual(decoded.hotkey, .controlShift)
        XCTAssertTrue(decoded.beep)
    }

    func testEncodeRoundTrip() {
        for hotkey in Hotkey.presets {
            for beep in [false, true] {
                let decoded = OpenKeySettings.decodeSwitchKey(OpenKeySettings.encodeSwitchKey(hotkey, beep: beep))
                XCTAssertEqual(decoded.hotkey, hotkey)
                XCTAssertEqual(decoded.beep, beep)
            }
        }
    }

    func testApplyOnlyPresentKeys() {
        var base = Preferences()
        base.excludedApps = ["a.b"]
        let p = OpenKeySettings.apply(["InputType": 1, "ModernOrthography": 1, "vOtherLanguage": 0,
                                       "UseSmartSwitchKey": 0, "SwitchKeyStatus": 0x8000 | 0x900 | 0xFE,
                                       "GrayIcon": 0, "vFixChromiumBrowser": 1], to: base)
        XCTAssertEqual(p.inputType, .vni)
        XCTAssertTrue(p.modernOrthography)
        XCTAssertFalse(p.disableOnNonEnglishInputSource)
        XCTAssertFalse(p.rememberPerApp)
        XCTAssertEqual(p.hotkey, Hotkey(modifiers: [.control, .shift]))
        XCTAssertTrue(p.beepOnSwitch)
        XCTAssertFalse(p.modernMenuIcon)
        XCTAssertTrue(p.fixChromiumBrowser)
        // Keys absent from the data keep their values
        XCTAssertTrue(p.checkSpelling)
        XCTAssertEqual(p.excludedApps, ["a.b"])
    }

    func testInvalidInputTypeIgnored() {
        XCTAssertEqual(OpenKeySettings.apply(["InputType": 7], to: Preferences()).inputType, .telex)
    }

    func testResetToDefaultsKeepsLanguageAndExclusions() {
        var p = Preferences()
        p.vietnamese = false
        p.excludedApps = ["x"]
        p.quickTelex = true
        p.hotkey = .controlSpace
        let r = p.resetToDefaults()
        XCTAssertFalse(r.vietnamese)
        XCTAssertEqual(r.excludedApps, ["x"])
        XCTAssertFalse(r.quickTelex)
        XCTAssertEqual(r.hotkey, .controlShift)
    }
}
