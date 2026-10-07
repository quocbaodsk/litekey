import XCTest
import Dispatch
import LiteKeyEngine
@testable import LiteKeyCore

/// Time per key through the whole decision path (hotkey, engine, planner), without posting events.
/// The threshold is loose for CI (debug build, VMs); the figure is printed. Budget: 1 ms per key.
final class ProcessorPerformanceTests: XCTestCase {
    func testAverageKeyTimeThroughProcessor() {
        // "tieengs vieejt khoong daáu " in Telex, US key codes
        let keys: [UInt16] = [17, 34, 14, 14, 5, 1, 49, 9, 34, 14, 14, 38, 17, 49,
                              40, 4, 31, 31, 45, 5, 49, 2, 0, 0, 1, 32, 49]
        for id in ["com.google.Chrome", "com.apple.Terminal", AppRules.spotlight] {
            let prefs = Preferences()
            var p = KeyEventProcessor(engine: VietnameseEngine(config: prefs.engineConfig), preferences: prefs,
                                      context: AppContext(bundleID: id, rules: .builtIn, preferences: prefs))
            var plan = InjectionPlan()
            let rounds = 2000
            let start = DispatchTime.now().uptimeNanoseconds
            for _ in 0..<rounds {
                for code in keys {
                    _ = p.handle(KeyEvent(kind: .keyDown, keyCode: code, time: 1), plan: &plan)
                }
            }
            let perKey = Double(DispatchTime.now().uptimeNanoseconds - start) / Double(rounds * keys.count) / 1000
            print("Processor (\(id)): average \(String(format: "%.2f", perKey)) µs/key")
            XCTAssertLessThan(perKey, 200, id)
        }
    }
}
