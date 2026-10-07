import XCTest
@testable import LiteKeyCore

/// Switch hotkey detection (`HotkeyStateMachine`).
final class HotkeyTests: XCTestCase {
    // Raw flags as macOS sends them (with device-dependent bits): left ⌃ = 0x40101, left ⇧ = 0x20102...
    let ctrl = ModifierFlags(rawValue: 0x40101)
    let ctrlShift = ModifierFlags(rawValue: 0x60103)
    let shift = ModifierFlags(rawValue: 0x20102)
    let option = ModifierFlags(rawValue: 0x80120)
    let cmd = ModifierFlags(rawValue: 0x100108)
    let none = ModifierFlags(rawValue: 0x100)

    func testOptionZFiresOnKeyDown() {
        var m = HotkeyStateMachine(hotkey: .optionZ)
        XCTAssertEqual(m.flagsChanged(option), HotkeyFlagsResult())
        XCTAssertTrue(m.keyDown(keyCode: KeyCode.z, flags: option))
        // Releasing ⌥ after using the hotkey: no temporary off
        XCTAssertEqual(m.flagsChanged(none), HotkeyFlagsResult())
    }

    func testOptionZNeedsExactModifiers() {
        var m = HotkeyStateMachine(hotkey: .optionZ)
        _ = m.flagsChanged(option)
        _ = m.flagsChanged(ModifierFlags(rawValue: 0xA0122)) // ⌥⇧
        XCTAssertFalse(m.keyDown(keyCode: KeyCode.z, flags: ModifierFlags(rawValue: 0xA0122)))
    }

    func testZWithoutModifierIsNotHotkey() {
        var m = HotkeyStateMachine(hotkey: .optionZ)
        XCTAssertFalse(m.keyDown(keyCode: KeyCode.z, flags: none))
    }

    func testModifierOnlyFiresOnFirstRelease() {
        var m = HotkeyStateMachine(hotkey: .controlShift)
        XCTAssertFalse(m.flagsChanged(ctrl).toggle)
        XCTAssertFalse(m.flagsChanged(ctrlShift).toggle)
        XCTAssertTrue(m.flagsChanged(shift).toggle)   // release ⌃ first
        XCTAssertFalse(m.flagsChanged(none).toggle)
    }

    func testModifierOnlyCancelledByOtherKey() {
        var m = HotkeyStateMachine(hotkey: .controlShift)
        _ = m.flagsChanged(ctrl)
        _ = m.flagsChanged(ctrlShift)
        XCTAssertFalse(m.keyDown(keyCode: 8, flags: ctrlShift)) // ⌃⇧C
        XCTAssertFalse(m.flagsChanged(shift).toggle)
    }

    // MARK: Tap only

    private let ms: UInt64 = 1_000_000

    func testQuickTapToggles() {
        var m = HotkeyStateMachine(hotkey: .controlShift)
        _ = m.flagsChanged(ctrl, time: 1000 * ms)
        _ = m.flagsChanged(ctrlShift, time: 1050 * ms)
        XCTAssertTrue(m.flagsChanged(shift, time: 1400 * ms).toggle)
    }

    func testLongHoldDoesNotToggleOrTempOff() {
        var m = HotkeyStateMachine(hotkey: .controlShift)
        _ = m.flagsChanged(ctrl, time: 1000 * ms)
        _ = m.flagsChanged(ctrlShift, time: 1050 * ms)
        XCTAssertEqual(m.flagsChanged(shift, time: 1600 * ms), HotkeyFlagsResult())
        XCTAssertEqual(m.flagsChanged(none, time: 1700 * ms), HotkeyFlagsResult())
        var c = HotkeyStateMachine(hotkey: .optionZ)
        _ = c.flagsChanged(ctrl, time: 1000 * ms)
        XCTAssertEqual(c.flagsChanged(none, time: 2000 * ms), HotkeyFlagsResult())
    }

    func testClickCancelsUntilAllModifiersReleased() {
        var m = HotkeyStateMachine(hotkey: .controlShift)
        _ = m.flagsChanged(ctrl)
        _ = m.flagsChanged(ctrlShift)
        m.cancel()
        XCTAssertFalse(m.flagsChanged(shift).toggle)
        XCTAssertFalse(m.flagsChanged(ctrlShift).toggle)  // ⌃ pressed again while ⇧ still held from the click
        XCTAssertFalse(m.flagsChanged(shift).toggle)
        XCTAssertFalse(m.flagsChanged(none).toggle)
        // Everything released: the next tap works
        _ = m.flagsChanged(ctrl)
        _ = m.flagsChanged(ctrlShift)
        XCTAssertTrue(m.flagsChanged(shift).toggle)
    }

    func testCommandClickIsNotTempOff() {
        var m = HotkeyStateMachine(hotkey: .optionZ)
        _ = m.flagsChanged(cmd)
        m.cancel()
        XCTAssertEqual(m.flagsChanged(none), HotkeyFlagsResult())
    }

    func testExtraModifierSpoilsUntilAllReleased() {
        var m = HotkeyStateMachine(hotkey: .controlShift)
        let ctrlShiftOption = ModifierFlags(rawValue: 0xE0123)
        _ = m.flagsChanged(ctrl)
        _ = m.flagsChanged(ctrlShift)
        _ = m.flagsChanged(ctrlShiftOption)
        XCTAssertEqual(m.flagsChanged(ctrlShift), HotkeyFlagsResult())  // ⌥ up: ⌃⌥⇧ is not the hotkey
        XCTAssertEqual(m.flagsChanged(ctrl), HotkeyFlagsResult())       // ⇧ up: not ⌃⇧ either
        XCTAssertEqual(m.flagsChanged(none), HotkeyFlagsResult())       // ⌃ up: not a ⌃ tap
        // A clean gesture works again
        _ = m.flagsChanged(ctrl)
        _ = m.flagsChanged(ctrlShift)
        XCTAssertTrue(m.flagsChanged(shift).toggle)
    }

    func testCapitalTypedWithShiftThenControlTapToggles() {
        // ⇧ held for a capital is typing, not a shortcut
        var m = HotkeyStateMachine(hotkey: .controlShift)
        _ = m.flagsChanged(shift)
        XCTAssertFalse(m.keyDown(keyCode: 0, flags: shift))
        _ = m.flagsChanged(ctrlShift)
        XCTAssertTrue(m.flagsChanged(shift).toggle)
    }

    func testOtherModifierTapWhileShiftHeldSpoilsUntilShiftUp() {
        var m = HotkeyStateMachine(hotkey: .controlShift)
        _ = m.flagsChanged(shift)
        _ = m.flagsChanged(ModifierFlags(rawValue: 0x12010A)) // ⌘⇧
        XCTAssertEqual(m.flagsChanged(shift), HotkeyFlagsResult())
        _ = m.flagsChanged(ctrlShift)
        XCTAssertFalse(m.flagsChanged(shift).toggle)
        _ = m.flagsChanged(none)
        _ = m.flagsChanged(ctrl)
        _ = m.flagsChanged(ctrlShift)
        XCTAssertTrue(m.flagsChanged(shift).toggle)
    }

    func testLongHoldReleaseLeavingShiftDownBlocksNextTap() {
        var m = HotkeyStateMachine(hotkey: .controlShift)
        _ = m.flagsChanged(ctrl, time: 1_000)
        _ = m.flagsChanged(ctrlShift, time: 2_000)
        XCTAssertFalse(m.flagsChanged(shift, time: 2_000 + HotkeyStateMachine.maxTap + 1).toggle)
        _ = m.flagsChanged(ctrlShift, time: 3_000_000_000)
        XCTAssertFalse(m.flagsChanged(shift, time: 3_000_000_001).toggle)
    }

    func testControlWithAnotherModifierIsNotTempOff() {
        var m = HotkeyStateMachine(hotkey: .optionZ)
        _ = m.flagsChanged(ctrl)
        _ = m.flagsChanged(ModifierFlags(rawValue: 0xC0121)) // ⌃⌥
        XCTAssertEqual(m.flagsChanged(ctrl), HotkeyFlagsResult())
        XCTAssertEqual(m.flagsChanged(none), HotkeyFlagsResult())
    }

    func testShortcutReleasedInStepsIsNotTempOff() {
        // ⌃⇧A, then ⇧ up before ⌃: ⌃ was used in a shortcut
        var m = HotkeyStateMachine(hotkey: .optionZ)
        _ = m.flagsChanged(ctrl)
        _ = m.flagsChanged(ctrlShift)
        XCTAssertFalse(m.keyDown(keyCode: 0, flags: ctrlShift))
        XCTAssertEqual(m.flagsChanged(ctrl), HotkeyFlagsResult())
        XCTAssertEqual(m.flagsChanged(none), HotkeyFlagsResult())
    }

    func testKeyWithoutModifiersClearsSpoiledGesture() {
        // The final release was never seen (tap re-enabled, Secure Input): the next plain key resets
        var m = HotkeyStateMachine(hotkey: .controlShift)
        _ = m.flagsChanged(ctrl)
        m.cancel()
        XCTAssertFalse(m.keyDown(keyCode: 0, flags: none))
        _ = m.flagsChanged(ctrl)
        _ = m.flagsChanged(ctrlShift)
        XCTAssertTrue(m.flagsChanged(shift).toggle)
    }

    func testCancelWithoutModifiersIsNoOp() {
        var m = HotkeyStateMachine(hotkey: .controlShift)
        m.cancel()
        _ = m.flagsChanged(ctrl)
        _ = m.flagsChanged(ctrlShift)
        XCTAssertTrue(m.flagsChanged(shift).toggle)
    }

    func testHoldingShiftAndTappingControlTwiceTogglesTwice() {
        var m = HotkeyStateMachine(hotkey: .controlShift)
        _ = m.flagsChanged(shift)
        _ = m.flagsChanged(ctrlShift)
        XCTAssertTrue(m.flagsChanged(shift).toggle)
        _ = m.flagsChanged(ctrlShift)
        XCTAssertTrue(m.flagsChanged(shift).toggle)
    }

    func testModifierOnlyNotFiredBySubset() {
        var m = HotkeyStateMachine(hotkey: .controlShift)
        _ = m.flagsChanged(ctrl)
        XCTAssertFalse(m.flagsChanged(none).toggle)
    }

    func testControlReleaseReportsTempOff() {
        var m = HotkeyStateMachine(hotkey: .optionZ)
        _ = m.flagsChanged(ctrl)
        XCTAssertEqual(m.flagsChanged(none), HotkeyFlagsResult(controlReleased: true))
    }

    func testCommandReleaseReportsTempOff() {
        var m = HotkeyStateMachine(hotkey: .optionZ)
        _ = m.flagsChanged(cmd)
        XCTAssertEqual(m.flagsChanged(none), HotkeyFlagsResult(commandReleased: true))
    }

    func testControlUsedInShortcutStillReportsAfterKeyResetsLastFlag() {
        // ⌃C: keyDown clears lastFlag, so releasing ⌃ only records flags and reports nothing
        var m = HotkeyStateMachine(hotkey: .optionZ)
        _ = m.flagsChanged(ctrl)
        XCTAssertFalse(m.keyDown(keyCode: 8, flags: ctrl))
        XCTAssertEqual(m.flagsChanged(none), HotkeyFlagsResult())
    }

    func testHotkeyKeyWithWrongModifiersMarksJustUsed() {
        // Z pressed while holding ⌃ (not ⌥Z): lastFlag unchanged, hasJustUsed = true
        var m = HotkeyStateMachine(hotkey: .optionZ)
        _ = m.flagsChanged(ctrl)
        XCTAssertFalse(m.keyDown(keyCode: KeyCode.z, flags: ctrl))
        XCTAssertEqual(m.flagsChanged(none), HotkeyFlagsResult())
    }

    func testEmptyHotkeyNeverFires() {
        var m = HotkeyStateMachine(hotkey: Hotkey(modifiers: []))
        _ = m.flagsChanged(ctrl)
        XCTAssertFalse(m.flagsChanged(none).toggle)
        XCTAssertFalse(m.keyDown(keyCode: KeyCode.z, flags: none))
    }

    func testKeyWithoutModifierNeverFiresAndKeyStillTypes() {
        // Unchecking every modifier of ⌥Z: plain Z must not become the switch hotkey
        let hotkey = Hotkey(modifiers: [], keyCode: KeyCode.z)
        XCTAssertFalse(hotkey.isUsable)
        var m = HotkeyStateMachine(hotkey: hotkey)
        XCTAssertFalse(m.keyDown(keyCode: KeyCode.z, flags: none))
        _ = m.flagsChanged(option)
        _ = m.flagsChanged(none)
        XCTAssertFalse(m.keyDown(keyCode: KeyCode.z, flags: none))
    }

    func testCannotRemoveLastModifierWhenKeyIsSet() {
        XCTAssertFalse(Hotkey.optionZ.canRemove(.option))
        XCTAssertTrue(Hotkey.optionZ.canRemove(.control))
        XCTAssertTrue(Hotkey(modifiers: [.control, .option], keyCode: KeyCode.z).canRemove(.option))
    }

    func testModifierOnlyHotkeyKeepsTwoKeys() {
        XCTAssertFalse(Hotkey.controlShift.canRemove(.control))
        XCTAssertFalse(Hotkey.controlShift.canRemove(.shift))
        XCTAssertTrue(Hotkey(modifiers: [.control, .option, .shift]).canRemove(.option))
        // Already below two keys (old settings): removing stays blocked, adding is the way out
        XCTAssertFalse(Hotkey(modifiers: [.control]).canRemove(.control))
    }

    func testSingleModifierIsUnusableAndNeverFires() {
        let hotkey = Hotkey(modifiers: [.control])
        XCTAssertEqual(hotkey.keyCount, 1)
        XCTAssertFalse(hotkey.isUsable)
        var m = HotkeyStateMachine(hotkey: hotkey)
        _ = m.flagsChanged(ctrl)
        // Not the toggle: releasing ⌃ alone keeps its own meaning
        XCTAssertEqual(m.flagsChanged(none), HotkeyFlagsResult(controlReleased: true))
    }

    func testKeyCountIgnoresNonHotkeyFlags() {
        var hotkey = Hotkey.controlShift
        hotkey.modifiers.insert(.capsLock)
        XCTAssertEqual(hotkey.keyCount, 2)
        XCTAssertEqual(Hotkey.optionZ.keyCount, 2)
        XCTAssertEqual(Hotkey(modifiers: []).keyCount, 0)
    }

    func testClearingKey() {
        XCTAssertEqual(Hotkey(modifiers: [.control, .shift], keyCode: KeyCode.space).clearingKey(), .controlShift)
        // ⌥ alone would be one key: rejected
        XCTAssertNil(Hotkey.optionZ.clearingKey())
    }

    func testRecordingUsesHeldModifiers() {
        XCTAssertEqual(Hotkey.controlShift.recording(keyCode: KeyCode.z, held: option),
                       Hotkey(modifiers: [.option], keyCode: KeyCode.z))
        // No modifiers held: use the checked boxes
        XCTAssertEqual(Hotkey.controlShift.recording(keyCode: KeyCode.space, held: none),
                       Hotkey(modifiers: [.control, .shift], keyCode: KeyCode.space))
        // No modifiers at all: rejected
        XCTAssertNil(Hotkey(modifiers: []).recording(keyCode: KeyCode.z, held: none))
    }

    func testImportedOpenKeyHotkeyWithoutModifierIsUnusable() {
        // Imported switch key status: key Z (6), no ⌃ ⌥ ⌘ ⇧ bits
        let hotkey = OpenKeySettings.decodeSwitchKey(6).hotkey
        XCTAssertEqual(hotkey.keyCode, KeyCode.z)
        XCTAssertFalse(hotkey.isUsable)
        XCTAssertFalse(hotkey.matches(flags: [], keyCode: KeyCode.z))
    }

    func testTitles() {
        XCTAssertEqual(Hotkey.optionZ.title, "⌥ + Z")
        XCTAssertEqual(Hotkey.controlShift.title, "⌃ + ⇧")
        XCTAssertEqual(Hotkey.controlSpace.title, "⌃ + Space")
    }
}
