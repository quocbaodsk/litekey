import CoreGraphics
import Foundation
import LiteKeyCore
import LiteKeyEngine

/// Event tap → `KeyEventProcessor` → `StepExecutor`.
///
/// Everything runs on main (the tap lives on the main run loop), so the processor is touched from a
/// single thread. Effects the app must hear about (mode toggled by hotkey) are dispatched
/// asynchronously so the callback returns immediately.
public final class KeyboardPipeline<Engine: TypingEngine> {
    private var processor: KeyEventProcessor<Engine>
    private var plan = InjectionPlan()
    private let executor = StepExecutor()
    private var settleGate = SettleGate()
    private let diagnostics: Diagnostics
    private var tap: EventTap!

    /// Vietnamese/English mode was toggled by hotkey (called on main with the new value)
    public var onLanguageToggled: ((Bool) -> Void)?
    /// The tap was disabled after Accessibility permission was lost (called on main; tap already stopped)
    public var onPermissionLost: (() -> Void)?
    /// macOS kept disabling the tap, so it was removed to avoid hanging the keyboard (called on main; tap
    /// already stopped)
    public var onGaveUp: (() -> Void)?
    /// The key recipient may have changed (called inside the callback; must return immediately)
    public var onFocusHint: (() -> Void)?

    public init(engine: Engine, preferences: Preferences, context: AppContext, diagnostics: Diagnostics) {
        processor = KeyEventProcessor(engine: engine, preferences: preferences, context: context)
        self.diagnostics = diagnostics
        tap = EventTap(handler: { [unowned self] proxy, type, event in
            self.handle(proxy: proxy, type: type, event: event)
        }, onMouseDown: { [unowned self] in
            self.mouseDown()
        })
        tap.onReenabled = { [unowned self] type in
            self.processor.newSession()
            self.settleGate.reset()
            self.diagnostics.tapDisabled(byTimeout: type == .tapDisabledByTimeout)
        }
        tap.onPermissionLost = { [unowned self] in self.onPermissionLost?() }
        tap.onGaveUp = { [unowned self] in
            self.diagnostics.tapGaveUp()
            self.onGaveUp?()
        }
    }

    public var isRunning: Bool { tap.isRunning }

    /// Debug builds always time the callback (warning above 1ms); release builds only when logging is on
    private var measureTiming: Bool {
        #if DEBUG
        return true
        #else
        return diagnostics.isEnabled
        #endif
    }

    @discardableResult
    public func start() -> Bool {
        guard tap.start() else { return false }
        settleGate.reset()
        newSession()
        return true
    }

    public func stop() {
        tap.stop()
    }

    /// Disables the tap immediately from any thread (permission loss is detected off main); main removes it
    /// later with `stop()`
    public func disableNow() {
        tap.disable()
    }

    /// Watchdog: checks that the tap is still enabled. Call on main, periodically and after wake or
    /// screen unlock. Returns the decision so the app can handle permission loss.
    @discardableResult
    public func checkHealth(trusted: Bool) -> TapHealth.Action {
        let action = TapHealth.check(tapInstalled: tap.isRunning, tapEnabled: tap.isEnabled, trusted: trusted)
        if action == .reenable, tap.reenableIfNeeded() {
            newSession()
            diagnostics.watchdogReenabled()
        }
        return action
    }

    public func update(preferences: Preferences) {
        processor.update(preferences: preferences)
    }

    public func update(context: AppContext) {
        processor.update(context: context)
    }

    public func newSession() {
        processor.newSession()
    }

    public func update(macros: MacroTable) {
        processor.update(macros: macros)
    }

    /// Mouse click in another app (seen by the global monitor, not the tap): start a new word
    private func mouseDown() {
        let decision = processor.handle(KeyEvent(kind: .mouseDown), plan: &plan)
        if decision.focusMayChange { onFocusHint?() }
    }

    private func handle(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        guard var keyEvent = EventNormalizer.normalize(type: type, event: event) else {
            return Unmanaged.passUnretained(event)
        }
        keyEvent.time = DispatchTime.now().uptimeNanoseconds
        // A real key arrived before the app finished processing the keys just injected (only for apps
        // with `settle`, such as Terminal): wait out the remainder first. keyUp needs no wait.
        var settled: UInt32 = 0
        if keyEvent.kind != .keyUp {
            let wait = settleGate.wait(at: keyEvent.time)
            if wait > 0 { settled = StepExecutor.sleep(wait) }
        }
        let start = measureTiming ? DispatchTime.now().uptimeNanoseconds : 0
        let decision = processor.handle(keyEvent, plan: &plan)
        if !plan.isEmpty {
            executor.execute(plan, original: event, proxy: proxy)
            settleGate.injected(settle: plan.settle, at: DispatchTime.now().uptimeNanoseconds)
        }
        if decision.languageToggled {
            let vietnamese = processor.preferences.vietnamese
            DispatchQueue.main.async { [weak self] in self?.onLanguageToggled?(vietnamese) }
        }
        if decision.focusMayChange {
            onFocusHint?()
        }
        if measureTiming {
            diagnostics.key(keyEvent, decision: decision, output: processor.lastOutput, plan: plan,
                            context: processor.context,
                            nanoseconds: DispatchTime.now().uptimeNanoseconds - start,
                            sleptMicroseconds: plan.isEmpty ? 0 : executor.lastSleep,
                            settledMicroseconds: settled,
                            vietnamese: processor.preferences.vietnamese)
        }
        return decision.passThrough ? Unmanaged.passUnretained(event) : nil
    }
}
