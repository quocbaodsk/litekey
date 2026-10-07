import XCTest
@testable import LiteKeyEngine

/// Restore-if-wrong-spelling after backspacing over a space into the previous word (differs from the fixtures).
final class RestoreTests: XCTestCase {
    private func type(_ keys: String, restore: Bool = true) -> String {
        var config = EngineConfig()
        config.restoreIfWrong = restore
        var sim = ScreenSimulator(engine: VietnameseEngine(config: config))
        return sim.type(keys)
    }

    func testRestoreAfterDeletingIntoPreviousWordKeepsLetters() {
        // Restoring would give "pace ": it deletes 5 letters but retypes only 4 keys
        XCTAssertEqual(type("sapce maf<<<<<<pace "), "sâpce ")
        XCTAssertEqual(type("sapce maf<<<<<<pace ", restore: false), "sâpce ")
    }

    func testRestoreStillWorksWhenKeysAreKnown() {
        // Backspacing within the word, or over a space before another word is typed: still restores
        XCTAssertEqual(type("sapace "), "sapace ")
        XCTAssertEqual(type("sapce<<<pace "), "sapace ")
        XCTAssertEqual(type("sa<<sapace "), "sapace ")
    }

    func testNewSessionAfterMisspelledWordStartsFresh() {
        // Mouse click / app switch right after a misspelled word: the next word must still take marks
        for restore in [true, false] {
            var config = EngineConfig()
            config.restoreIfWrong = restore
            var sim = ScreenSimulator(engine: VietnameseEngine(config: config))
            XCTAssertEqual(sim.type("baanfk"), "bầnk", "restore=\(restore)")
            XCTAssertEqual(sim.type("as"), "á", "restore=\(restore)")
            XCTAssertEqual(sim.type("vieetj "), "việt ", "restore=\(restore)")
        }
    }

    func testBackspaceAcrossWordsSentence() {
        XCTAssertEqual(type("xoas laos, xoas sapce maf<<<<<<pace xoas "), "xóa láo, xóa sâpce xóa ")
    }
}

/// Word history (`_typingStates`) stays bounded when typing without line breaks.
final class TypingHistoryTests: XCTestCase {
    func testHistoryIsBounded() {
        var sim = ScreenSimulator(engine: VietnameseEngine())
        _ = sim.type(String(repeating: "vieetj nam ", count: 500))
        XCTAssertLessThanOrEqual(sim.engine._typingStates.count, VietnameseEngine.maxTypingStates)
        // Backspacing over a space can still fix marks in the previous word
        XCTAssertEqual(sim.type("tooi vieet <j "), "tôi việt ")
    }
}

/// Quick start/end consonants on words that nearly fill the 32-slot buffer.
final class QuickConsonantBufferTests: XCTestCase {
    private func type(_ keys: String) -> String {
        var config = EngineConfig()
        config.checkSpelling = false
        config.quickStartConsonant = true
        config.quickEndConsonant = true
        var sim = ScreenSimulator(engine: VietnameseEngine(config: config))
        return sim.type(keys)
    }

    func testLongWordIsLeftAlone() {
        // Without the limit, "f" + 30 "b" + space put a garbage character before "ph…" and lost the last letter
        for count in 29...31 {
            let word = "f" + String(repeating: "b", count: count)
            XCTAssertEqual(type(word + " "), word + " ", "\(count + 1) characters")
        }
        // 29 characters: adding "h" still fits the buffer
        let bs = String(repeating: "b", count: 28)
        XCTAssertEqual(type("f" + bs + " "), "ph" + bs + " ")
    }

    func testShortWordsStillUseQuickConsonants() {
        XCTAssertEqual(type("fas "), "phá ")
        XCTAssertEqual(type("cag "), "cang ")
    }
}
