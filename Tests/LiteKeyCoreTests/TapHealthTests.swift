import XCTest
@testable import LiteKeyCore

final class TapHealthTests: XCTestCase {
    func testDecisions() {
        XCTAssertEqual(TapHealth.check(tapInstalled: false, tapEnabled: false, trusted: false), .none)
        XCTAssertEqual(TapHealth.check(tapInstalled: true, tapEnabled: true, trusted: true), .none)
        XCTAssertEqual(TapHealth.check(tapInstalled: true, tapEnabled: false, trusted: true), .reenable)
        XCTAssertEqual(TapHealth.check(tapInstalled: true, tapEnabled: true, trusted: false), .stopForPermission)
        XCTAssertEqual(TapHealth.check(tapInstalled: true, tapEnabled: false, trusted: false), .stopForPermission)
    }

    func testSecureInputMessage() {
        XCTAssertNil(SecureInputState().message)
        XCTAssertEqual(SecureInputState(enabled: true, ownerName: "Terminal").message,
                       "Đang nhập mật khẩu (Secure Input) trong Terminal: tạm thời không gõ tiếng Việt")
        XCTAssertNotNil(SecureInputState(enabled: true).message)
    }
}

final class TapDisableGuardTests: XCTestCase {
    private let second: UInt64 = 1_000_000_000

    func testStopsImmediatelyWithoutPermission() {
        var guardian = TapDisableGuard()
        XCTAssertEqual(guardian.tapDisabled(at: 0, trusted: false), .stop)
    }

    func testReenablesOccasionalTimeouts() {
        var guardian = TapDisableGuard()
        XCTAssertEqual(guardian.tapDisabled(at: 0, trusted: true), .reenable)
        XCTAssertEqual(guardian.tapDisabled(at: 20 * second, trusted: true), .reenable)
        XCTAssertEqual(guardian.tapDisabled(at: 40 * second, trusted: true), .reenable)
    }

    func testReenablesSporadicDisablesLikeSecureInput() {
        // Several password fields in a row: macOS disables the tap a few times; the tap must not be dropped
        var guardian = TapDisableGuard()
        for i: UInt64 in 0..<10 {
            XCTAssertEqual(guardian.tapDisabled(at: i * second, trusted: true), .reenable)
        }
    }

    func testGivesUpOnBurstOfDisables() {
        // Stale permission (cached AXIsProcessTrusted) with the tap disabled right after each re-enable: drop the tap rather than freeze
        var guardian = TapDisableGuard()
        let step = second / 5
        for i: UInt64 in 0..<4 {
            XCTAssertEqual(guardian.tapDisabled(at: i * step, trusted: true), .reenable)
        }
        XCTAssertEqual(guardian.tapDisabled(at: 4 * step, trusted: true), .stop)
    }

    func testResetForgetsHistory() {
        var guardian = TapDisableGuard()
        _ = guardian.tapDisabled(at: 0, trusted: true)
        _ = guardian.tapDisabled(at: 1 * second, trusted: true)
        guardian.reset()
        XCTAssertEqual(guardian.tapDisabled(at: 2 * second, trusted: true), .reenable)
    }
}
