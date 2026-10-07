import XCTest
@testable import LiteKeyEngine

/// `TypingHistory` behaves like the array of arrays it replaces.
final class TypingHistoryStorageTests: XCTestCase {
    func testPushPopOrderAndContents() {
        var history = TypingHistory(entries: 4, elementsPerEntry: 2)
        history.append([1, 2, 3])
        history.append([])
        history.append([4])
        XCTAssertEqual(history.count, 3)
        var entry: [UInt32] = [9, 9]
        history.removeLast(into: &entry)
        XCTAssertEqual(entry, [4])
        history.removeLast(into: &entry)
        XCTAssertEqual(entry, [])
        history.removeLast(into: &entry)
        XCTAssertEqual(entry, [1, 2, 3])
        XCTAssertEqual(history.count, 0)
    }

    func testRemoveFirstDropsOldestEntries() {
        var history = TypingHistory(entries: 4, elementsPerEntry: 2)
        for n in 1...5 { history.append([UInt32](repeating: UInt32(n), count: n)) }
        history.removeFirst(2)
        XCTAssertEqual(history.count, 3)
        var entry: [UInt32] = []
        history.removeLast(into: &entry)
        XCTAssertEqual(entry, [5, 5, 5, 5, 5])
        history.append([7])
        history.removeLast(into: &entry)
        XCTAssertEqual(entry, [7])
        history.removeLast(into: &entry)
        XCTAssertEqual(entry, [4, 4, 4, 4])
        history.removeLast(into: &entry)
        XCTAssertEqual(entry, [3, 3, 3])
        XCTAssertEqual(history.count, 0)
        history.removeFirst(0)
        XCTAssertEqual(history.count, 0)
    }

    func testRemoveAll() {
        var history = TypingHistory(entries: 4, elementsPerEntry: 2)
        history.append([1])
        history.removeAll()
        XCTAssertEqual(history.count, 0)
        history.append([2])
        var entry: [UInt32] = []
        history.removeLast(into: &entry)
        XCTAssertEqual(entry, [2])
    }
}
