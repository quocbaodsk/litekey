import Foundation
import LiteKeyCore
import LiteKeyEngine
import os

/// Diagnostic logging via os_log. Off by default; enable with
/// `defaults write <bundle ID> DebugLogging -bool YES` and relaunch the app.
///
/// When enabled, each key logs: event kind, key code, decision, engine output (backspaces/text) and
/// processing time in the callback. Typed text is logged as public so logs can be shared for
/// debugging; turn logging off when done.
public final class Diagnostics {
    public static let defaultsKey = "DebugLogging"

    public let isEnabled: Bool
    private let logger: Logger
    private var timeouts = 0

    public init(subsystem: String, enabled: Bool) {
        self.isEnabled = enabled
        self.logger = Logger(subsystem: subsystem, category: "tap")
        if enabled { logger.notice("Diagnostic logging enabled") }
    }

    /// macOS disabled the tap (always logged, even when logging is off)
    public func tapDisabled(byTimeout: Bool) {
        timeouts += 1
        logger.error("Tap disabled (\(byTimeout ? "timeout" : "user input", privacy: .public)), count \(self.timeouts, privacy: .public); re-enabled and started a new word")
    }

    /// The tap kept getting disabled and was removed (always logged)
    public func tapGaveUp() {
        logger.fault("macOS kept disabling the tap: removed it so the keyboard does not hang. Relaunch LiteKey or grant Accessibility permission again.")
    }

    /// The watchdog found the tap silently disabled and re-enabled it (always logged)
    public func watchdogReenabled() {
        logger.error("Watchdog: tap was disabled; re-enabled and started a new word")
    }

    /// One key: detailed line when logging is on; otherwise warns only if the callback took > 1 ms (debug
    /// builds time every key)
    public func key(_ event: KeyEvent, decision: KeyDecision, output: EngineOutput, plan: InjectionPlan,
                    context: AppContext, nanoseconds: UInt64, sleptMicroseconds: UInt32,
                    settledMicroseconds: UInt32 = 0, vietnamese: Bool = true) {
        let work = Double(nanoseconds) / 1_000_000 - Double(sleptMicroseconds) / 1000
        guard isEnabled else {
            if work > 1 {
                logger.warning("SLOW: callback took \(String(format: "%.3f", work), privacy: .public)ms (excluding intentional delays)")
            }
            return
        }
        let text = String(decoding: output.text, as: UTF16.self)
        let verdict = decision.passThrough ? "pass" : "swallow"
        let app = context.bundleID ?? "?"
        let line = "\(event.kind) key=\(event.keyCode) flags=0x\(String(event.flags.rawValue, radix: 16)) -> \(verdict) bs=\(output.backspaces) text=\"\(text)\" steps=\(plan.steps.count) app=\(app) spotlight=\(context.isSpotlight) vi=\(vietnamese) inputEN=\(context.inputSourceIsEnglish) \(String(format: "%.3f", work))ms sleep=\(sleptMicroseconds)µs settle=\(settledMicroseconds)µs"
        if work > 1 {
            logger.warning("SLOW \(line, privacy: .public)")
        } else {
            logger.notice("\(line, privacy: .public)")
        }
    }

    /// Other Vietnamese input methods running alongside (always logged when present)
    public func otherInputMethods(_ names: [String]) {
        guard !names.isEmpty else { return }
        logger.error("Running alongside another input method: \(names.joined(separator: ", "), privacy: .public). Two input methods handling the same keys will drop characters")
    }

    /// Older LiteKey copies asked to quit at launch (always logged when present)
    public func olderCopiesQuit(_ names: [String]) {
        guard !names.isEmpty else { return }
        logger.notice("Asked older LiteKey copies to quit: \(names.joined(separator: ", "), privacy: .public)")
    }

    public func note(_ message: String) {
        guard isEnabled else { return }
        logger.info("\(message, privacy: .public)")
    }
}
