import XCTest
@testable import LiteKeyEngine

/// The fixtures (Tests/fixtures) are reference data and cannot be regenerated.
/// The engine must match every row except those in `FixtureExceptions`, which deliberately differ.
final class FixtureTests: XCTestCase {
    func testSwiftEngineMatchesAllFixtures() throws {
        try check(VietnameseEngine())
    }

    func testExceptionsAreRealFixtureRows() throws {
        // Each exception must name a real row whose fixture result differs (no hiding rows that still match)
        let rows = try FixtureRunner<VietnameseEngine>.loadRows()
        let byKey = Dictionary(uniqueKeysWithValues: rows.map { ("\($0.file):\($0.line)", $0) })
        for (key, value) in FixtureExceptions.restoreAfterDeletingIntoPreviousWord {
            let row = try XCTUnwrap(byKey[key], key)
            XCTAssertNotEqual(row.expected, value, key)
            XCTAssertTrue(row.keys.contains("<"), key)
        }
    }

    private func check<E: TypingEngine>(_ engine: E, file: StaticString = #filePath, line: UInt = #line) throws {
        let rows = try FixtureRunner<E>.loadRows()
        XCTAssertGreaterThan(rows.count, 10_000, file: file, line: line)
        var runner = FixtureRunner(engine: engine)
        let failures = runner.run(rows)
        XCTAssertTrue(failures.isEmpty, "\(failures.count)/\(rows.count) rows failed:\n" +
                      failures.prefix(30).map(\.description).joined(separator: "\n"), file: file, line: line)
    }
}
