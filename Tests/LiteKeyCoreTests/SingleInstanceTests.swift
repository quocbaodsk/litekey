import XCTest
@testable import LiteKeyCore

final class SingleInstanceTests: XCTestCase {
    private typealias Copy = SingleInstance.Copy

    func testNewestCopyAsksOlderOnesToQuit() {
        let own = Copy(pid: 300, launchedAt: 1_000)
        let others = [Copy(pid: 100, launchedAt: 900), Copy(pid: 200, launchedAt: 950)]
        XCTAssertEqual(SingleInstance.olderCopies(than: own, among: others), [100, 200])
    }

    func testOlderCopyLeavesNewerOneAlone() {
        let own = Copy(pid: 100, launchedAt: 900)
        XCTAssertEqual(SingleInstance.olderCopies(than: own, among: [Copy(pid: 300, launchedAt: 1_000)]), [])
    }

    func testAloneOrOnlySelfListed() {
        let own = Copy(pid: 100, launchedAt: 900)
        XCTAssertEqual(SingleInstance.olderCopies(than: own, among: []), [])
        XCTAssertEqual(SingleInstance.olderCopies(than: own, among: [own]), [])
    }

    func testSameLaunchTimeQuitsOnlyOneSide() {
        let a = Copy(pid: 100, launchedAt: 900)
        let b = Copy(pid: 200, launchedAt: 900)
        XCTAssertEqual(SingleInstance.olderCopies(than: b, among: [a]), [100])
        XCTAssertEqual(SingleInstance.olderCopies(than: a, among: [b]), [])
    }

    func testUnknownLaunchTimeQuitsNothingFromEitherSide() {
        // Both views of the same pair: whichever side has the unknown time, nobody quits
        let known = Copy(pid: 300, launchedAt: 1_000)
        let unknown = Copy(pid: 400, launchedAt: nil)
        XCTAssertEqual(SingleInstance.olderCopies(than: known, among: [unknown]), [])
        XCTAssertEqual(SingleInstance.olderCopies(than: unknown, among: [known]), [])
    }
}
