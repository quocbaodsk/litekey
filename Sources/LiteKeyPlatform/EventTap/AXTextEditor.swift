import ApplicationServices
import Foundation
import LiteKeyCore

/// Experimental: replaces the word before the caret through Accessibility (`AXEdit`), on its own thread.
///
/// The tap callback never calls AX: it hands one edit over with `start` and returns. The next key waits in
/// `result(waitingUpTo:)` until the edit is done, so keys stay in order. Every AX call goes to the focused
/// process with a short timeout, and no call starts after `readBudget`, so an edit finishes within
/// `maxDuration`. Only the focused element is touched: no tree walk, roles or DOM attributes, which push
/// Chrome/Electron into their slower accessibility mode.
public final class AXTextEditor {
    enum Outcome: Equatable {
        case replaced
        /// Nothing was changed (or the selection was put back): inject with key events instead
        case failed
    }

    /// `defaults write <bundle ID> AXEdit -bool NO` turns the AX edit off (relaunch to apply)
    public static let defaultsKey = "AXEdit"
    /// Failures in a row after which an app goes back to key events until relaunch
    static let maxFailures = 3

    /// Timeout of each AX call (the process-wide default is FocusProbe's 0.25 s). A launcher busy searching
    /// may miss it; that edit then falls back to key events.
    static let callTimeout: Float = 0.025
    /// Reads past this (ns) give up before writing anything
    static let readBudget: UInt64 = 50_000_000
    /// Worst case of one edit, and how long the next key waits for it: the read budget, one read that
    /// crosses it, then select, replace, read back and put the selection back
    static let maxDuration: UInt64 = readBudget + 5 * UInt64(callTimeout * 1_000_000_000)

    private let request = DispatchSemaphore(value: 0)
    private let finished = DispatchSemaphore(value: 0)
    private let onFinished: () -> Void
    // Handed over through the semaphores: written by the caller before `request.signal()`, by the worker
    // before `finished.signal()`
    private var pid: pid_t = 0
    private var deleting = 0
    private var units: [UInt16] = []
    private var outcome = Outcome.failed
    /// Duration of the last edit (ns), for logging
    private(set) var lastDuration: UInt64 = 0

    /// `onFinished` runs on the worker thread after each edit
    init(onFinished: @escaping () -> Void) {
        self.onFinished = onFinished
        units.reserveCapacity(64)
        // Lives as long as the app, like the pipeline that owns it
        let thread = Thread { [self] in run() }
        thread.name = "LiteKey.AXTextEditor"
        thread.qualityOfService = .userInteractive
        thread.start()
    }

    /// Starts an edit in process `pid`: delete `deleting` units before the caret and insert `text`. Call
    /// only when no edit is in flight. No allocation while `text` fits the reserved buffer.
    func start(pid: pid_t, deleting: Int, text: ArraySlice<UInt16>) {
        self.pid = pid
        self.deleting = deleting
        units.removeAll(keepingCapacity: true)
        units.append(contentsOf: text)
        request.signal()
    }

    /// The outcome of the edit in flight, waiting at most `nanoseconds`; `nil` if it is still running.
    /// Each edit's outcome is returned exactly once.
    func result(waitingUpTo nanoseconds: UInt64) -> Outcome? {
        finished.wait(timeout: .now() + .nanoseconds(Int(nanoseconds))) == .success ? outcome : nil
    }

    private func run() {
        while true {
            request.wait()
            let start = DispatchTime.now().uptimeNanoseconds
            outcome = edit(start: start)
            lastDuration = DispatchTime.now().uptimeNanoseconds - start
            finished.signal()
            onFinished()
        }
    }

    private func edit(start: UInt64) -> Outcome {
        // Never this process: the tap waits on main for the edit, and main would have to answer
        guard pid > 0, pid != getpid() else { return .failed }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, Self.callTimeout)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return .failed }
        let field = value as! AXUIElement
        AXUIElementSetMessagingTimeout(field, Self.callTimeout)
        guard let selected = range(field, kAXSelectedTextRangeAttribute) else { return .failed }
        let total = int(field, kAXNumberOfCharactersAttribute)
        guard DispatchTime.now().uptimeNanoseconds - start < Self.readBudget,
              let target = AXEdit.replaceRange(caret: selected.location, selection: selected.length,
                                               total: total, deleting: deleting) else { return .failed }
        guard setRange(field, CFRange(location: target.location, length: target.length)) else { return .failed }
        let text = units.withUnsafeBufferPointer { buffer in
            CFStringCreateWithCharacters(nil, buffer.baseAddress, buffer.count)
        }
        let written = text.map { AXUIElementSetAttributeValue(field, kAXSelectedTextAttribute as CFString, $0) }
        // A timed-out write may still be applied later: typing the fallback too could double the word
        if written == .cannotComplete { return .replaced }
        if written == .success {
            // Some fields report success and ignore the write: the replaced range would still be selected.
            // Any other answer (or none) counts as done, so the fallback never types the word twice.
            guard let after = range(field, kAXSelectedTextRangeAttribute),
                  after.location == target.location && after.length == target.length && target.length > 0
            else { return .replaced }
        }
        // Put the selection back, or the fallback's first backspace would delete the whole selected range
        _ = setRange(field, selected)
        return .failed
    }

    private func range(_ element: AXUIElement, _ attribute: String) -> CFRange? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var range = CFRange()
        return AXValueGetValue(value as! AXValue, .cfRange, &range) ? range : nil
    }

    private func int(_ element: AXUIElement, _ attribute: String) -> Int? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return (value as? NSNumber)?.intValue
    }

    private func setRange(_ element: AXUIElement, _ range: CFRange) -> Bool {
        var range = range
        guard let value = AXValueCreate(.cfRange, &range) else { return false }
        return AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, value) == .success
    }
}
