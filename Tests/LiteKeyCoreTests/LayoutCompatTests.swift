import XCTest
@testable import LiteKeyCore

final class LayoutCompatTests: XCTestCase {
    func testUSKeyCodeTable() {
        XCTAssertEqual(LayoutCompat.usKeyCode(for: "a"), 0)
        XCTAssertEqual(LayoutCompat.usKeyCode(for: "A"), 0)
        XCTAssertEqual(LayoutCompat.usKeyCode(for: "!"), 18)
        XCTAssertEqual(LayoutCompat.usKeyCode(for: "&"), 26)
        XCTAssertEqual(LayoutCompat.usKeyCode(for: "é"), nil)
        XCTAssertEqual(LayoutCompat.usKeyCode(for: "ab"), nil)
    }

    func testMapUsesShiftTable() {
        // AZERTY: key 18 gives "&" unshifted and "1" with Shift
        let map = KeyboardLayoutMap { code, shift in code == 18 ? (shift ? "1" : "&") : nil }
        XCTAssertEqual(map.map(18, shift: false), 26)
        XCTAssertEqual(map.map(18, shift: true), 18)
        XCTAssertEqual(map.map(0, shift: false), 0)
        XCTAssertEqual(map.map(200, shift: false), 200)
    }

    func testUSCharacters() {
        XCTAssertEqual(LayoutCompat.usCharacter(for: 6), "z")
        XCTAssertEqual(LayoutCompat.usCharacter(for: 18), "1")
        XCTAssertEqual(KeyNames.name(for: 6), "Z")
    }
}
