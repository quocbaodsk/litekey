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
    // Experimental AX edit (`Preferences.fixOverlayLauncher`, `AppContext.axEdit`), main thread only
    private var axEditor: AXTextEditor?
    /// Plan of the edit in flight: its fallback or remaining steps run once the edit finishes
    private var axPlan = InjectionPlan()
    private var axOriginal: CGEvent?
    private var axPending = false
    /// The edit in flight ran past `AXTextEditor.maxDuration`: keys stop waiting for it
    private var axStalled = false
    /// App of the edit in flight, consecutive failures there, and apps where AX was given up for this run
    private var axApp: String?
    private var axFailures = 0
    private var axGaveUp: Set<String> = []

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
        // Edit done with no key waiting for it: finish on main
        axEditor = AXTextEditor { [weak self] in
            DispatchQueue.main.async { self?.finishAXEdit(proxy: nil, waitingUpTo: 0) }
        }
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
            // An AX edit still running: this key must land after it. Deliberate wait in the callback, capped
            // like the per-app delays (ARCHITECTURE.md, experimental AX edit).
            if axPending { settled += finishAXEdit(proxy: proxy, waitingUpTo: axStalled ? 0 : AXTextEditor.maxDuration) }
        }
        let start = measureTiming ? DispatchTime.now().uptimeNanoseconds : 0
        let decision = processor.handle(keyEvent, plan: &plan)
        var usedAX = false
        if !plan.isEmpty {
            usedAX = startAXEdit(original: event)
            if !usedAX { executor.execute(plan, original: event, proxy: proxy) }
            // `startAXEdit` moved this key's plan to `axPlan`
            settleGate.injected(settle: usedAX ? axPlan.settle : plan.settle, at: DispatchTime.now().uptimeNanoseconds)
        }
        if decision.languageToggled {
            let vietnamese = processor.preferences.vietnamese
            DispatchQueue.main.async { [weak self] in self?.onLanguageToggled?(vietnamese) }
        }
        if decision.focusMayChange {
            onFocusHint?()
        }
        if measureTiming {
            diagnostics.key(keyEvent, decision: decision, output: processor.lastOutput, plan: usedAX ? axPlan : plan,
                            context: processor.context,
                            nanoseconds: DispatchTime.now().uptimeNanoseconds - start,
                            sleptMicroseconds: plan.isEmpty || usedAX ? 0 : executor.lastSleep,
                            settledMicroseconds: settled,
                            vietnamese: processor.preferences.vietnamese)
        }
        return decision.passThrough ? Unmanaged.passUnretained(event) : nil
    }

    // MARK: - Experimental AX edit

    /// Hands the plan's AX edit to the editor; `false` = inject with key events as usual
    private func startAXEdit(original: CGEvent) -> Bool {
        guard let axEditor, let edit = plan.axEdit, !axPending else { return false }
        let context = processor.context
        // "" stands for an app without a bundle ID, so it can be given up on too
        let app = (context.spotlightActive ? context.overlayBundleID : context.bundleID) ?? ""
        if axGaveUp.contains(app) { return false }
        swap(&plan, &axPlan)
        if app != axApp { axFailures = 0 }
        axApp = app
        // The copy is needed only to repost the key after the edit (allocates, like `.repostOriginal` itself)
        axOriginal = axPlan.steps.contains(.repostOriginal) ? original.copy() : nil
        axPending = true
        axEditor.start(pid: context.focusedPID, deleting: edit.deleting,
                       text: axPlan.text[edit.textStart ..< edit.textStart + edit.textCount])
        return true
    }

    /// Waits up to `nanoseconds` for the AX edit in flight, then runs the steps it left: the key event
    /// fallback if it failed, the rest of the plan either way. Returns the time waited (µs).
    @discardableResult
    private func finishAXEdit(proxy: CGEventTapProxy?, waitingUpTo nanoseconds: UInt64) -> UInt32 {
        guard axPending, let axEditor, let edit = axPlan.axEdit else { return 0 }
        let start = DispatchTime.now().uptimeNanoseconds
        let outcome = axEditor.result(waitingUpTo: nanoseconds)
        let waited = UInt32(truncatingIfNeeded: (DispatchTime.now().uptimeNanoseconds - start) / 1000)
        guard let outcome else {
            // Past its worst case (AX timeouts not honored): stop holding keys and give up AX in this app
            if proxy != nil, !axStalled {
                axStalled = true
                axGaveUp.insert(axApp ?? "")
                diagnostics.axEditStalled(app: axApp)
            }
            return waited
        }
        axPending = false
        if axStalled {
            // Later keys already went through: replaying the fallback or the repost now would land after
            // them and garble the text. Drop the steps and start a new word, since the screen is unknown.
            axStalled = false
            processor.newSession()
        } else {
            executor.execute(axPlan, from: outcome == .replaced ? edit.fallbackEnd : 0, original: axOriginal,
                             proxy: proxy)
        }
        axOriginal = nil
        if outcome == .replaced {
            axFailures = 0
        } else {
            axFailures += 1
            // Allocates, but only on a failure that already cost an AX round trip
            if axFailures >= AXTextEditor.maxFailures {
                axGaveUp.insert(axApp ?? "")
                axFailures = 0
            }
        }
        if diagnostics.isEnabled {
            diagnostics.axEdit(replaced: outcome == .replaced, app: axApp, nanoseconds: axEditor.lastDuration,
                               waitedMicroseconds: waited, gaveUp: axGaveUp.contains(axApp ?? ""))
        }
        return waited
    }
}
