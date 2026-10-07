import XCTest
@testable import LiteKeyCore

final class OtherInputMethodsTests: XCTestCase {
    func testFindsKnownInputMethods() {
        let apps: [(bundleID: String?, name: String?)] = [
            ("com.apple.finder", "Finder"),
            ("com.tuyenmai.openkey", "OpenKey"),
            ("com.codetay.XKey", "XKey"),
            ("com.lamquangminh.evkey", "EVKey"),
            ("com.microsoft.VSCode", "Code"),
            ("com.litekey.app", "LiteKey"),
        ]
        XCTAssertEqual(OtherInputMethods.running(apps, ownBundleID: "com.litekey.app"), ["OpenKey", "XKey", "EVKey"])
    }

    func testMatchesByNameWhenBundleUnknown() {
        XCTAssertEqual(OtherInputMethods.running([(nil, "GoTiengViet"), ("org.example.UniKeyMac", nil)], ownBundleID: nil),
                       ["GoTiengViet", "org.example.UniKeyMac"])
    }

    func testIgnoresOwnAppAndUnrelatedApps() {
        let apps: [(bundleID: String?, name: String?)] = [("com.litekey.app", "LiteKey"), ("com.apple.Safari", "Safari")]
        XCTAssertEqual(OtherInputMethods.running(apps, ownBundleID: "com.litekey.app"), [])
        XCTAssertNil(OtherInputMethods.message([]))
        XCTAssertEqual(OtherInputMethods.message(["OpenKey"]),
                       "Đang chạy cùng bộ gõ khác: OpenKey. Hãy thoát bộ gõ đó để không mất chữ")
    }
}
