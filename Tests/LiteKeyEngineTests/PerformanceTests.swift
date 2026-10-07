import XCTest
@testable import LiteKeyEngine

/// Measures the engine's time per key across all fixtures.
/// The threshold is loose to stay stable on CI (debug build, VMs); the actual figure is printed.
final class PerformanceTests: XCTestCase {
    func testAverageKeyTimeIsWellUnderOneMillisecond() throws {
        let rows = try FixtureRunner<VietnameseEngine>.loadRows()
        var runner = FixtureRunner(engine: VietnameseEngine())
        let keys = rows.reduce(0) { $0 + $1.keys.count }
        let start = DispatchTime.now().uptimeNanoseconds
        _ = runner.run(rows)
        let perKey = Double(DispatchTime.now().uptimeNanoseconds - start) / Double(keys) / 1000
        print("Engine: \(keys) keys, average \(String(format: "%.2f", perKey)) µs/key (including screen simulation)")
        XCTAssertLessThan(perKey, 200)
    }
}
