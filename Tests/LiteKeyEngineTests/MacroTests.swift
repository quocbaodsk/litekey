import Foundation
import XCTest
@testable import LiteKeyEngine

final class MacroTests: XCTestCase {
    private let sample = """
    ;Compatible OpenKey Macro Data file for UniKey*** version=1 ***
    btw:by the way
    vn:Việt Nam
    :):vui
    :a:hai chấm a
    btw:trùng (giữ mục đầu)
    khong-co-dau-hai-cham
    url:http://a.b:80/c
    """

    func testReadMacroFile() {
        var table = MacroTable()
        table.load(fileText: sample, append: false)
        let macros = Dictionary(uniqueKeysWithValues: table.macros.map { ($0.text, $0.content) })
        XCTAssertEqual(macros["btw"], "by the way")
        XCTAssertEqual(macros["vn"], "Việt Nam")
        XCTAssertEqual(macros[":)"], "vui")
        XCTAssertEqual(macros[":a"], "hai chấm a")
        XCTAssertEqual(macros["url"], "http://a.b:80/c")
        XCTAssertEqual(table.count, 5)
    }

    func testCRLFFile() {
        var table = MacroTable()
        table.load(fileText: ";header\r\nbtw:by the way\r\nko:không\r\n", append: false)
        XCTAssertEqual(Set(table.macros), [Macro(text: "btw", content: "by the way"), Macro(text: "ko", content: "không")])
    }

    func testAppendKeepsExisting() {
        var table = MacroTable(macros: [Macro(text: "a", content: "anh")])
        table.load(fileText: ";h\nb:bạn\na:em\n", append: true)
        XCTAssertEqual(Set(table.macros), [Macro(text: "a", content: "anh"), Macro(text: "b", content: "bạn")])
        table.load(fileText: ";h\nb:bạn\n", append: false)
        XCTAssertEqual(table.macros, [Macro(text: "b", content: "bạn")])
    }

    func testAddEditDelete() {
        var table = MacroTable()
        table.add("ms", content: "milli")
        table.add("ms", content: "millisecond")
        XCTAssertEqual(table.macros, [Macro(text: "ms", content: "millisecond")])
        XCTAssertTrue(table.has("ms"))
        XCTAssertFalse(table.has("Ms"))
        XCTAssertTrue(table.delete("ms"))
        XCTAssertFalse(table.delete("ms"))
        XCTAssertTrue(table.isEmpty)
    }

    func testFileTextRoundTrip() {
        var table = MacroTable()
        table.load(fileText: sample, append: false)
        var again = MacroTable()
        again.load(fileText: table.fileText, append: false)
        XCTAssertEqual(again.macros, table.macros)
        XCTAssertTrue(table.fileText.hasPrefix(MacroTable.fileHeader + "\n"))
    }

    func testOpenKeyBinaryRoundTrip() {
        var table = MacroTable()
        table.load(fileText: sample, append: false)
        XCTAssertEqual(MacroTable(openKeyData: table.openKeyData).macros, table.macros)
        XCTAssertTrue(MacroTable(openKeyData: [5]).isEmpty)
        XCTAssertTrue(MacroTable(openKeyData: [2, 0, 3, 0x61]).isEmpty) // truncated
    }

    func testOpenKeyBinarySkipsMacrosTooLongForFormat() {
        // The text length has only 1 byte: writing a longer one would lose the whole table on read
        let long = String(repeating: "x", count: 300)
        let table = MacroTable(macros: [Macro(text: long, content: "dài"), Macro(text: "b", content: "bạn"),
                                        Macro(text: "c", content: String(repeating: "y", count: 70_000))])
        XCTAssertEqual(MacroTable(openKeyData: table.openKeyData).macros, [Macro(text: "b", content: "bạn")])
        let edge = MacroTable(macros: [Macro(text: String(repeating: "z", count: 255), content: "đủ")])
        XCTAssertEqual(MacroTable(openKeyData: edge.openKeyData).macros, edge.macros)
    }

    /// Parsing the macro file and encoding the binary format must produce exactly these bytes.
    func testOpenKeyBinaryMatchesReferenceBytes() {
        let openKey: [UInt8] = [
            0x05, 0x00, 0x02, 0x76, 0x6E, 0x0A, 0x00, 0x56, 0x69, 0xE1, 0xBB, 0x87, 0x74, 0x20, 0x4E, 0x61,
            0x6D, 0x03, 0x62, 0x74, 0x77, 0x0A, 0x00, 0x62, 0x79, 0x20, 0x74, 0x68, 0x65, 0x20, 0x77, 0x61,
            0x79, 0x03, 0x75, 0x72, 0x6C, 0x0F, 0x00, 0x68, 0x74, 0x74, 0x70, 0x3A, 0x2F, 0x2F, 0x61, 0x2E,
            0x62, 0x3A, 0x38, 0x30, 0x2F, 0x63, 0x02, 0x3A, 0x61, 0x0C, 0x00, 0x68, 0x61, 0x69, 0x20, 0x63,
            0x68, 0xE1, 0xBA, 0xA5, 0x6D, 0x20, 0x61, 0x02, 0x3A, 0x29, 0x03, 0x00, 0x76, 0x75, 0x69,
        ]
        var table = MacroTable()
        table.load(fileText: sample, append: false)
        XCTAssertEqual(table.openKeyData, openKey)
        XCTAssertEqual(MacroTable(openKeyData: openKey).openKeyData, openKey)
    }

    func testEmojiContentIsSentAsSurrogatePair() {
        var engine = VietnameseEngine(config: EngineConfig(useMacro: true))
        engine.setMacros(MacroTable(macros: [Macro(text: "vui", content: "😀!")]))
        var out = EngineOutput()
        for code: UInt16 in [9, 32, 34] { engine.handleKey(code: code, caps: .none, otherModifier: false, into: &out) }
        engine.handleKey(code: 49, caps: .none, otherModifier: false, into: &out)
        XCTAssertEqual(out.action, .macro)
        XCTAssertEqual(out.backspaces, 3)
        XCTAssertEqual(String(decoding: out.characters.map(\.unit), as: UTF16.self), "😀!")
        XCTAssertEqual(out.restoreKey?.keyCode, 49)
    }
}
