import XCTest
@testable import LiteKeyEngine

/// Typing fixes for key sequences whose output used to be wrong.
private func type(_ keys: String, _ config: EngineConfig = EngineConfig()) -> String {
    var sim = ScreenSimulator(engine: VietnameseEngine(config: config))
    return sim.type(keys)
}

/// A circumflex on ơ removes the horn from the ư before it; the screen must show that too.
final class CircumflexRedrawTests: XCTestCase {
    func testCircumflexAfterHornedPairRedrawsEarlierVowel() {
        XCTAssertEqual(type("nguwowio"), "nguôi")
        XCTAssertEqual(type("nguwowio "), "nguôi ")
        XCTAssertEqual(type("cuoiwo"), "cuôi")
        XCTAssertEqual(type("uowo"), "uô")
    }

    func testScreenMatchesBufferWhenAToneFollows() {
        // A tone redraws the whole vowel group from the buffer; the result must not change
        XCTAssertEqual(type("cuoiwos"), "cuối")
        XCTAssertEqual(type("nguwowios"), "nguối")
    }

    func testHornedWordsWithoutCircumflexUnchanged() {
        XCTAssertEqual(type("tuwowi"), "tươi")
        XCTAssertEqual(type("nguwowif "), "người ")
        XCTAssertEqual(type("toot"), "tôt")
    }

    func testVNI() {
        let vni = EngineConfig(inputType: .vni)
        XCTAssertEqual(type("nguo7i6 ", vni), "nguôi ")
        XCTAssertEqual(type("nguo7i2 ", vni), "người ")
    }
}

/// A standalone ư (typed with w) keeps its horn when a circumflex is added next to it. It used to lose the
/// horn in the buffer, and when the tone moved onto the circumflex it vanished from the screen ("wfaa" gave "ầ").
final class StandaloneHornCircumflexTests: XCTestCase {
    func testStandaloneHornIsNotLost() {
        XCTAssertEqual(type("wfaa"), "ưầ")
        XCTAssertEqual(type("wsaa"), "ưấ")
        XCTAssertEqual(type("Wfaa"), "Ưầ")
        XCTAssertEqual(type("WFAA"), "ƯẦ")
        XCTAssertEqual(type("wfoo"), "ưồ")
        XCTAssertEqual(type("wjoo"), "ưộ")
        XCTAssertEqual(type("wfee"), "ưề")
        XCTAssertEqual(type("waa"), "ưâ")
        XCTAssertEqual(type("woo"), "ưô")
    }

    func testBackspaceMatchesScreen() {
        // The buffer used to hold a plain u that the screen never showed
        XCTAssertEqual(type("wfaa<"), "ư")
        XCTAssertEqual(type("wfoo<"), "ư")
        XCTAssertEqual(type("wfaa<<"), "")
        XCTAssertEqual(type("wfaa<n"), "ưn")
    }

    func testRestoreOnSpace() {
        // "ưâ" is not Vietnamese, so restore-if-wrong gives back the keys; the next word is unaffected
        XCTAssertEqual(type("wfaa "), "wfaa ")
        XCTAssertEqual(type("wfaa tooi "), "wfaa tôi ")
        var config = EngineConfig()
        config.restoreIfWrong = false
        XCTAssertEqual(type("wfaa ", config), "ưầ ")
        XCTAssertEqual(type("woong ", config), "ưông ")
    }

    func testWAfterCircumflexKeepsHorn() {
        // w turns â back into a and keeps the ư, as with a regular horn ("tuwaaw" → "tưa")
        XCTAssertEqual(type("waaw"), "ưa")
        XCTAssertEqual(type("waaws "), "ứa ")
        XCTAssertEqual(type("wfaaw"), "ừa")
        XCTAssertEqual(type("wfaaw<"), "ừ")
        XCTAssertEqual(type("tuwaaw"), "tưa")
        XCTAssertEqual(type("woow "), "ươ ")
        // The letters before the ư used to vanish ("tương")
        XCTAssertEqual(type("thwoowng "), "thương ")
        XCTAssertEqual(type("thwoows "), "thướ ")
        // A w on an already horned word still undoes the horn
        XCTAssertEqual(type("waw "), "uaw ")
        XCTAssertEqual(type("uwaw "), "uaw ")
    }

    func testThirdVowelUndoesCircumflex() {
        // Same as "ddd": the third key cancels the circumflex and is left out of the restore
        XCTAssertEqual(type("wfaaa"), "ừaa")
        XCTAssertEqual(type("wfaaa<<"), "ừ")
        XCTAssertEqual(type("waaa "), "waa ")
    }

    func testQuickStartConsonantRows() {
        // Some of the options.tsv rows listed in FixtureExceptions.standaloneHornKeepsHorn
        var config = EngineConfig()
        config.quickStartConsonant = true
        XCTAssertEqual(type("woong ", config), "woong ")
        XCTAssertEqual(type("wooj ", config), "wooj ")
        XCTAssertEqual(type("weens ", config), "weens ")
    }

    func testRegularHornStillGivesWayToCircumflex() {
        // A horn typed after u (not standalone) is still replaced by the circumflex
        XCTAssertEqual(type("tuwfaan "), "tuần ")
        XCTAssertEqual(type("tuwaan "), "tuân ")
        XCTAssertEqual(type("muwfaa"), "muầ")
        XCTAssertEqual(type("luwaaj"), "luậ")
        XCTAssertEqual(type("uwfee"), "uề")
        XCTAssertEqual(type("uwfee<"), "u")
        XCTAssertEqual(type("thuwoo"), "thuô")
        XCTAssertEqual(type("cuwowio"), "cuôi")
        XCTAssertEqual(type("huwowngr "), "hưởng ")
    }

    func testVNI() {
        let vni = EngineConfig(inputType: .vni)
        XCTAssertEqual(type("u72a6", vni), "uầ")
        XCTAssertEqual(type("u7a6", vni), "uâ")
        XCTAssertEqual(type("nguo7i6 ", vni), "nguôi ")
    }
}

/// A second w undoes the horn/breve on iơ, oă and thuơ, like it does on ươ.
final class SecondWUndoTests: XCTestCase {
    func testSecondWUndoesHornOnSecondVowel() {
        XCTAssertEqual(type("ioww"), "iow")
        XCTAssertEqual(type("oaww"), "oaw")
        XCTAssertEqual(type("hoaww "), "hoaw ")
        XCTAssertEqual(type("thuoww "), "thuow ")
    }

    func testSingleWStillAddsHorn() {
        XCTAssertEqual(type("hoawjc "), "hoặc ")
        XCTAssertEqual(type("thuowr "), "thuở ")
        XCTAssertEqual(type("thuowngf "), "thường ")
        XCTAssertEqual(type("kiowr"), "kiở")
    }

    func testExistingUndoCasesUnchanged() {
        XCTAssertEqual(type("muoww"), "muow")
        XCTAssertEqual(type("quoww"), "quow")
        XCTAssertEqual(type("ww"), "w")
    }

    func testVNI() {
        let vni = EngineConfig(inputType: .vni)
        XCTAssertEqual(type("io77", vni), "io7")
        XCTAssertEqual(type("hoa88 ", vni), "hoa8 ")
        XCTAssertEqual(type("thuo77 ", vni), "thuo7 ")
        XCTAssertEqual(type("hoa85c ", vni), "hoặc ")
    }
}

/// "Capitalize the first letter of a sentence" after "!" and "?" as well as ".".
final class SentenceEndCapitalizeTests: XCTestCase {
    /// Uses the fixture keyboard, which has Shift symbols such as "!" and "?"
    private func typeKeys(_ keys: String, _ config: String) -> String {
        var runner = FixtureRunner(engine: VietnameseEngine())
        return runner.type(.init(file: "", line: 0, config: config, keys: keys, expected: ""))
    }

    func testCapitalizesAfterExclamationAndQuestionMark() {
        XCTAssertEqual(typeKeys("xin chaof! ban ", "telex,upperfirst"), "xin chào! Ban ")
        XCTAssertEqual(typeKeys("xin chaof? ban ", "telex,upperfirst"), "xin chào? Ban ")
        XCTAssertEqual(typeKeys("xin chao2! ban ", "vni,upperfirst"), "xin chào! Ban ")
        XCTAssertEqual(typeKeys("xin chaof. ban ", "telex,upperfirst"), "xin chào. Ban ")
    }

    func testOtherPunctuationDoesNotCapitalize() {
        XCTAssertEqual(typeKeys("xin chaof/ ban ", "telex,upperfirst"), "xin chào/ ban ")
        XCTAssertEqual(typeKeys("xin chaof, ban ", "telex,upperfirst"), "xin chào, ban ")
        XCTAssertEqual(typeKeys("xin chaof!, ban ", "telex,upperfirst"), "xin chào!, ban ")
    }

    func testOptionOff() {
        XCTAssertEqual(typeKeys("xin chaof! ban ", "telex"), "xin chào! ban ")
    }
}
