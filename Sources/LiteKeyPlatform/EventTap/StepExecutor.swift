import CoreGraphics
import Foundation
import LiteKeyCore

/// Executes an `InjectionPlan` with CGEvents. Every event is tagged with `EventMarker` (via
/// `eventSourceUserData`) so the tap ignores it.
///
/// The Backspace down/up pair is created once and reused; other keys and Unicode text are created
/// fresh each time.
public final class StepExecutor {
    private let source = CGEventSource(stateID: .privateState)
    private let backspaceDown: CGEvent?
    private let backspaceUp: CGEvent?

    /// Total intentional sleep (measured) of the last execution, in microseconds, so logs can separate it
    /// from processing time
    public private(set) var lastSleep: UInt32 = 0

    public init() {
        backspaceDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(KeyCode.delete), keyDown: true)
        backspaceUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(KeyCode.delete), keyDown: false)
        for event in [backspaceDown, backspaceUp] {
            event?.setIntegerValueField(.eventSourceUserData, value: EventMarker.value)
        }
    }

    public func execute(_ plan: InjectionPlan, original: CGEvent, proxy: CGEventTapProxy) {
        lastSleep = 0
        for step in plan.steps {
            switch step {
            case let .key(code, flags):
                if code == KeyCode.delete && flags.isEmpty, let backspaceDown, let backspaceUp {
                    backspaceDown.tapPostEvent(proxy)
                    backspaceUp.tapPostEvent(proxy)
                } else {
                    tap(code, flags: CGEventFlags(rawValue: flags.rawValue), proxy: proxy)
                }
            case let .text(start, count):
                type(plan.text, start: start, count: count, proxy: proxy)
            case let .sleep(microseconds):
                lastSleep += Self.sleep(microseconds)
            case .repostOriginal:
                if let copy = original.copy() { post(copy, proxy: proxy) }
            }
        }
    }

    /// Sleeps and returns the actual time slept in microseconds. usleep often oversleeps; measuring keeps
    /// the log from reporting false slowness.
    public static func sleep(_ microseconds: UInt32) -> UInt32 {
        let start = DispatchTime.now().uptimeNanoseconds
        usleep(microseconds)
        return UInt32(truncatingIfNeeded: (DispatchTime.now().uptimeNanoseconds - start) / 1000)
    }

    private func tap(_ key: CGKeyCode, flags: CGEventFlags, proxy: CGEventTapProxy) {
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false) else { return }
        down.flags = flags
        up.flags = flags
        post(down, proxy: proxy)
        post(up, proxy: proxy)
    }

    private func type(_ text: [UInt16], start: Int, count: Int, proxy: CGEventTapProxy) {
        guard count > 0,
              let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else { return }
        text.withUnsafeBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return }
            down.keyboardSetUnicodeString(stringLength: count, unicodeString: base + start)
            up.keyboardSetUnicodeString(stringLength: count, unicodeString: base + start)
        }
        post(down, proxy: proxy)
        post(up, proxy: proxy)
    }

    private func post(_ event: CGEvent, proxy: CGEventTapProxy) {
        event.setIntegerValueField(.eventSourceUserData, value: EventMarker.value)
        event.tapPostEvent(proxy)
    }
}
