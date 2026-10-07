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

    func testStandaloneHornKeepsFixtureBehavior() {
        // options.tsv rows: a standalone ư before "oo"/"aa" is not redrawn
        var config = EngineConfig()
        config.quickStartConsonant = true
        XCTAssertEqual(type("woong ", config), "ưông ")
        XCTAssertEqual(type("waat ", config), "ưât ")
    }

    func testVNI() {
        let vni = EngineConfig(inputType: .vni)
        XCTAssertEqual(type("nguo7i6 ", vni), "nguôi ")
        XCTAssertEqual(type("nguo7i2 ", vni), "người ")
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
