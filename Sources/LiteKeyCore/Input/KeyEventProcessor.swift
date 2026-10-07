import LiteKeyEngine

/// Decision for one event: pass or swallow, plus side effects to report to the App layer.
public struct KeyDecision: Equatable, Sendable {
    /// `true` = return the original event to the system; `false` = swallow it (replaced by the plan's steps)
    public var passThrough: Bool
    /// The hotkey just toggled Vietnamese/English (the new value is in `preferences.vietnamese`)
    public var languageToggled: Bool
    /// Spotlight may have opened or closed (modifier + Space; inside Spotlight also ⌘+key, Esc, Enter,
    /// mouse click): FocusProbe should run again
    public var focusMayChange: Bool

    public init(passThrough: Bool, languageToggled: Bool = false, focusMayChange: Bool = false) {
        self.passThrough = passThrough
        self.languageToggled = languageToggled
        self.focusMayChange = focusMayChange
    }

    public static let pass = KeyDecision(passThrough: true)
    public static let swallow = KeyDecision(passThrough: false)
}

/// Drives the whole pipeline for one key:
///
/// 1. Switch hotkey (and temporary spell-check/engine off via ⌃/⌘ on modifier release)
/// 2. Mouse: start a new word
/// 3. English mode (macros only, if enabled) and excluded apps: pass
/// 4. Non-English system input source: pass (the switch hotkey is ignored too)
/// 5. Engine → `InjectionPlanner` (key repeats other than Backspace pass)
///
/// The key path does not allocate: `EngineOutput` and `InjectionPlan` are reused.
/// Use from a single thread (the event tap thread).
public struct KeyEventProcessor<Engine: TypingEngine> {
    public private(set) var preferences: Preferences
    public private(set) var context: AppContext
    private var engine: Engine
    private var hotkeys: HotkeyStateMachine
    private var output = EngineOutput()
    /// Until this uptime (ns), keys are assumed to go to Spotlight after ⌘Space; 0 = no assumption
    private var spotlightAssumedUntil: UInt64 = 0
    /// The caret may not be at the end of the text, so Forward Delete could delete real text
    private var caretMoved = false

    /// FocusProbe answers within 0.4 s of ⌘Space; the assumption covers the keys typed before that
    static var spotlightAssumption: UInt64 { 500_000_000 }

    public init(engine: Engine, preferences: Preferences, context: AppContext = AppContext()) {
        self.engine = engine
        self.preferences = preferences
        self.context = context
        self.context.isExcluded = context.excluded(by: preferences)
        self.hotkeys = HotkeyStateMachine(hotkey: preferences.hotkey)
        self.engine.configure(preferences.engineConfig)
        self.engine.newSession()
    }

    /// Engine output for the last key (for logging)
    public var lastOutput: EngineOutput { output }

    public mutating func update(preferences new: Preferences) {
        let old = preferences
        preferences = new
        hotkeys.hotkey = new.hotkey
        context.isExcluded = context.excluded(by: new)
        if old.engineConfig != new.engineConfig {
            engine.configure(new.engineConfig)
            engine.newSession()
        } else if old.vietnamese != new.vietnamese {
            engine.newSession()
        }
    }

    /// The key target changed. Starts a new word when the app or the system input source changes.
    public mutating func update(context new: AppContext) {
        // Keys typed under another input source (Japanese, Chinese...) never reached the engine, so the
        // old word must not be edited when coming back
        let targetChanged = new.bundleID != context.bundleID
            || new.inputSourceIsEnglish != context.inputSourceIsEnglish || new.layoutMap != context.layoutMap
        // Spotlight opened without ⌘Space (custom shortcut, menu): a fresh field. After ⌘Space, caret moves
        // since then are already tracked.
        if new.spotlightSuggestions && !context.spotlightSuggestions && spotlightAssumedUntil == 0 {
            caretMoved = false
        }
        if new.isSpotlight { spotlightAssumedUntil = 0 }
        context = new
        context.isExcluded = new.excluded(by: preferences)
        if targetChanged { engine.newSession() }
    }

    public mutating func newSession() {
        engine.newSession()
    }

    /// The macro table changed
    public mutating func update(macros: MacroTable) {
        engine.setMacros(macros)
    }

    public mutating func handle(_ event: KeyEvent, plan: inout InjectionPlan) -> KeyDecision {
        plan.reset()
        output.reset()
        guard context.sessionOnConsole, !context.suspended else { return .pass }

        var keyCode = event.keyCode
        let flags = event.flags

        // 1. Switch hotkey
        switch event.kind {
        case .keyDown:
            if preferences.layoutCompatibility {
                keyCode = context.layoutMap.map(keyCode, shift: flags.contains(.shift))
            }
            if hotkeys.keyDown(keyCode: keyCode, flags: flags), !languageLocked {
                toggleLanguage()
                return KeyDecision(passThrough: false, languageToggled: true)
            }
        case .flagsChanged:
            let result = hotkeys.flagsChanged(flags, time: event.time)
            if result.toggle {
                guard !languageLocked else { return .pass }
                toggleLanguage()
                return KeyDecision(passThrough: false, languageToggled: true)
            }
            if result.controlReleased && preferences.tempOffSpellingWithControl {
                engine.tempOffSpellChecking()
            }
            if result.commandReleased && preferences.tempOffEngineWithCommand {
                engine.tempOffEngine()
            }
            return .pass
        case .mouseDown, .mouseDragged:
            // ⌃⇧+click or ⌘+click is not a modifier tap
            hotkeys.cancel()
        case .keyUp:
            break
        }

        trackSpotlight(event)
        let focusMayChange = Self.focusMayChange(event, inSpotlight: context.isSpotlight)

        // 2. Mouse: start a new word, in every mode (also clears the macro buffer in English mode)
        if event.kind == .mouseDown || event.kind == .mouseDragged {
            engine.newSession()
            return KeyDecision(passThrough: true, focusMayChange: focusMayChange)
        }

        // 3. English mode (macros if `useMacroInEnglishMode` is on), excluded apps
        if context.isExcluded {
            return KeyDecision(passThrough: true, focusMayChange: focusMayChange)
        }
        guard preferences.vietnamese else {
            if preferences.useMacro && preferences.useMacroInEnglishMode && event.kind == .keyDown {
                let caps: CapsState = flags.contains(.shift) ? .shift : (flags.contains(.capsLock) ? .capsLock : .none)
                engine.handleEnglishModeKey(code: keyCode, caps: caps,
                                            otherModifier: !flags.isDisjoint(with: .otherControlMask), into: &output)
                if output.action == .macro {
                    InjectionPlanner.plan(output, context: context, preferences: preferences,
                                          clearInlineSuggestion: canClearInlineSuggestion, into: &plan)
                    return KeyDecision(passThrough: false, focusMayChange: focusMayChange)
                }
            }
            return KeyDecision(passThrough: true, focusMayChange: focusMayChange)
        }

        // 4. Non-English system input source
        if languageLocked {
            return .pass
        }

        // 5. Engine
        guard event.kind == .keyDown else { return .pass }
        // A held key repeats: pass the repeats untouched and start a new word, so holding "o" types "oooo"
        // instead of flipping between "ô" and "oo" with a burst of injections. Backspace repeats still reach
        // the engine, which follows each deletion.
        if event.isRepeat && keyCode != KeyCode.delete {
            engine.newSession()
            return KeyDecision(passThrough: true, focusMayChange: focusMayChange)
        }
        let caps: CapsState = flags.contains(.shift) ? .shift : (flags.contains(.capsLock) ? .capsLock : .none)
        let otherControl = !flags.isDisjoint(with: .otherControlMask)
        engine.handleKey(code: keyCode, caps: caps, otherModifier: otherControl, into: &output)
        // `.replace` (rewrite the word) or `.macro` (macro expansion)
        guard output.action != .pass else {
            return KeyDecision(passThrough: true, focusMayChange: focusMayChange)
        }
        // Spotlight may have opened: an empty char would land in its field. Plain backspaces work in any app.
        if spotlightAssumedUntil != 0 { output.noEmptyCharPrefix = true }
        InjectionPlanner.plan(output, context: context, preferences: preferences,
                              clearInlineSuggestion: canClearInlineSuggestion, into: &plan)
        return KeyDecision(passThrough: false, focusMayChange: focusMayChange)
    }

    /// The system input source turns Vietnamese off. The switch hotkey is ignored too: the menu would show V
    /// while nothing gets typed.
    private var languageLocked: Bool {
        preferences.disableOnNonEnglishInputSource && !context.inputSourceIsEnglish
    }

    /// Forward Delete needs Apple's Spotlight confirmed by FocusProbe and a caret known to be at the end
    private var canClearInlineSuggestion: Bool {
        context.spotlightSuggestions && !caretMoved
    }

    /// Assumes Spotlight for a moment after ⌘Space, and tracks whether the caret is still at the end.
    ///
    /// FocusProbe needs up to 0.4 s to see Spotlight; until then the keys would get the empty char. The
    /// assumption only drops the empty char, so a wrong guess (⌘Space bound to something else) is harmless.
    private mutating func trackSpotlight(_ event: KeyEvent) {
        if spotlightAssumedUntil != 0 && event.time >= spotlightAssumedUntil {
            spotlightAssumedUntil = 0
        }
        switch event.kind {
        case .mouseDown, .mouseDragged:
            spotlightAssumedUntil = 0
            caretMoved = true
        case .keyDown:
            let keyCode = event.keyCode
            let modifiers = event.flags.intersection(.hotkeyMask)
            if keyCode == KeyCode.space && modifiers == .command {
                if spotlightAssumedUntil == 0 && !context.isSpotlight && event.time > 0 {
                    spotlightAssumedUntil = event.time + Self.spotlightAssumption
                    caretMoved = false  // a fresh field
                } else {
                    // Spotlight closes: keys go back to a document before FocusProbe notices
                    spotlightAssumedUntil = 0
                    caretMoved = true
                }
                return
            }
            if keyCode == KeyCode.escape || keyCode == KeyCode.returnKey || keyCode == KeyCode.enter {
                spotlightAssumedUntil = 0
            }
            if keyCode == KeyCode.end
                || (modifiers.contains(.command) && (keyCode == KeyCode.rightArrow || keyCode == KeyCode.downArrow)) {
                caretMoved = false
            } else if keyCode == KeyCode.rightArrow && modifiers.isEmpty {
                // Stays at the end if it was there (accepting an inline suggestion moves to its end)
            } else if !modifiers.isDisjoint(with: [.command, .control]) || !Self.keepsCaretAtEnd(keyCode) {
                // Allowlist: anything but typing may move the caret (⌃A, ↑, ⌘A, Tab, Esc, Return...)
                caretMoved = true
            }
        default:
            break
        }
    }

    /// Keys that leave a caret at the end of the text if it was there: characters (main block, keypad) and Delete
    static func keepsCaretAtEnd(_ keyCode: UInt16) -> Bool {
        switch keyCode {
        case KeyCode.returnKey, KeyCode.tab, KeyCode.enter, KeyCode.keypadClear: return false
        case 0...KeyCode.delete, 65...92: return true
        default: return false
        }
    }

    private mutating func toggleLanguage() {
        preferences.vietnamese.toggle()
        engine.newSession()
    }

    /// Events that may open or close Spotlight, the only thing FocusProbe needs AX for.
    ///
    /// - Opening Spotlight: modifier + Space (⌘Space by default; users can remap it to ⌃/⌥ + Space).
    /// - Inside Spotlight: ⌘+key, Esc, Enter or a mouse click may close it.
    ///
    /// Outside Spotlight there is no re-probe after every Enter, Esc, click or ⌘C/⌘V: each probe makes three
    /// AX calls into the focused app, and Chrome/Electron may switch on their (slower) accessibility mode
    /// under frequent AX queries. App switches already arrive via NSWorkspace notifications, and while
    /// Spotlight is open FocusProbe re-probes every 0.5 s on its own.
    static func focusMayChange(_ event: KeyEvent, inSpotlight: Bool) -> Bool {
        switch event.kind {
        case .mouseDown:
            return inSpotlight
        case .keyDown:
            if event.keyCode == KeyCode.space && !event.flags.isDisjoint(with: [.command, .control, .option]) {
                return true
            }
            guard inSpotlight else { return false }
            if event.flags.contains(.command) { return true }
            return event.keyCode == KeyCode.escape || event.keyCode == KeyCode.returnKey || event.keyCode == KeyCode.enter
        default: return false
        }
    }
}
