import XCTest
@testable import LiteKeyCore

final class SettleGateTests: XCTestCase {
    private let ms: UInt64 = 1_000_000

    func testNoWaitByDefault() {
        XCTAssertEqual(SettleGate().wait(at: 123 * ms), 0)
    }

    func testWaitsOnlyForTheRemainder() {
        var gate = SettleGate()
        gate.injected(settle: 20000, at: 100 * ms)
        XCTAssertEqual(gate.wait(at: 100 * ms), 20000)
        XCTAssertEqual(gate.wait(at: 112 * ms), 8000)
        XCTAssertEqual(gate.wait(at: 120 * ms), 0)
        XCTAssertEqual(gate.wait(at: 500 * ms), 0)
    }

    func testPlanWithoutSettleClearsGate() {
        var gate = SettleGate()
        gate.injected(settle: 20000, at: 100 * ms)
        gate.injected(settle: 0, at: 101 * ms)
        XCTAssertEqual(gate.wait(at: 102 * ms), 0)
    }

    func testReset() {
        var gate = SettleGate()
        gate.injected(settle: 20000, at: 100 * ms)
        gate.reset()
        XCTAssertEqual(gate.wait(at: 100 * ms), 0)
    }
}
