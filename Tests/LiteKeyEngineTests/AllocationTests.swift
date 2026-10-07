#if canImport(Darwin)
import Darwin
import XCTest
@testable import LiteKeyEngine

/// Counts heap allocations through libmalloc's `malloc_logger` hook (macOS only).
private typealias MallocLogger = @convention(c) (UInt32, UInt, UInt, UInt, UInt, UInt32) -> Void
nonisolated(unsafe) private var mallocCount = 0
private let countingLogger: MallocLogger = { type, _, _, _, _, _ in
    if type & 2 != 0 { mallocCount &+= 1 } // MALLOC_LOG_TYPE_ALLOCATE
}

private func countAllocations(_ body: () -> Void) throws -> Int {
    let symbol = try XCTUnwrap(dlsym(UnsafeMutableRawPointer(bitPattern: -2), "malloc_logger"))
    let slot = symbol.assumingMemoryBound(to: Optional<MallocLogger>.self)
    mallocCount = 0
    slot.pointee = countingLogger
    body()
    slot.pointee = nil
    return mallocCount
}

/// The engine runs inside the event tap callback, so steady-state typing must not allocate.
/// Only meaningful in an optimized build, which is what ships:
/// `swift test -c release -Xswiftc -enable-testing --filter AllocationTests`
final class AllocationTests: XCTestCase {
    func testTypingWordsDoesNotAllocate() throws {
        // Unoptimized code allocates in places the optimizer removes (about 34 per word here)
        #if DEBUG
        let optimized = false
        #else
        let optimized = true
        #endif
        try XCTSkipUnless(optimized, "Allocation counts need an optimized build: swift test -c release -Xswiftc -enable-testing")
        // Words, punctuation, backspacing into the previous word and a word longer than the 32-slot buffer
        let sentence = "xin chaof, tooi laf nguwowif vieetj nam. dduowcj khoong <<<s supercalifragilisticexpialidociousxx "
        let keys = sentence.map { FixtureKeys.table[$0]! }
        var engine = VietnameseEngine()
        var output = EngineOutput()
        func typeSentence(times: Int) {
            for _ in 0..<times {
                for key in keys {
                    engine.handleKey(code: key.code, caps: key.shift ? .shift : .none, otherModifier: false, into: &output)
                }
            }
        }
        // Warm up: fill the word history past its bound once so every buffer reaches its working size
        typeSentence(times: 40)
        let repeats = 100
        let allocations = try countAllocations { typeSentence(times: repeats) }
        let words = repeats * sentence.split(separator: " ").count
        print("Engine allocations: \(allocations) for \(words) words (\(repeats * keys.count) keys)")
        // Other threads in the test process may allocate meanwhile, so allow a little noise
        XCTAssertLessThan(allocations, 20)
    }
}
#endif
