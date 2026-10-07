import LiteKeyEngine

/// Turns engine output into injection steps.
///
/// 1. Autocomplete fix: every app except Spotlight and terminals (`AppRule.autocompleteFix`), unless the
///    engine sets `noEmptyCharPrefix`.
///    Typing a character first replaces any inline autocomplete selection, so the backspaces delete real text.
///    - Chromium fix on Chromium apps: Shift+Left selects one character instead of the empty char
///    - otherwise: type an empty char U+202F (U+200C for Sublime Text), then delete one more
/// 2. Spotlight (and other overlay launchers): Forward Delete first when `clearInlineSuggestion`, then
///    replace via selection (Shift+Left × n) instead of backspaces
/// 3. Backspaces when `0 < n < 32`
/// 4. Type the new text (16 UTF-16 units per event), or send key by key
/// 5. Invalid word ended by a control key: repost the original key
///
/// Experimental: with `fixOverlayLauncher` on, apps with `AppContext.axEdit` also get `plan.axEdit` for a replacement with backspaces (not
/// macros, not key by key); the key event steps then serve as the fallback.
///
/// Apps listed in `AppRules` (terminals, JetBrains) also get `AppRule.delays` pauses between steps and a
/// `plan.settle` for the next real key.
public enum InjectionPlanner {
    /// Engine buffer size
    public static let maxBackspaces = 32

    /// `clearInlineSuggestion`: in Spotlight, the caret is known to be at the end of the text, so Forward
    /// Delete can only remove an auto-selected suggestion (see `selectForReplace`).
    public static func plan(_ output: EngineOutput, context: AppContext, preferences: Preferences,
                            clearInlineSuggestion: Bool = false, into plan: inout InjectionPlan) {
        plan.reset()
        switch output.action {
        case .pass: return
        case .macro:
            planMacro(output, context: context, preferences: preferences,
                      clearInlineSuggestion: clearInlineSuggestion, into: &plan)
            return
        case .replace: break
        }

        var backspaces = output.backspaces
        let rule = context.rule
        let spotlight = context.isSpotlight

        // 1. Autocomplete fix
        if preferences.fixRecommendBrowser && rule.autocompleteFix && !spotlight && !output.noEmptyCharPrefix {
            if preferences.fixChromiumBrowser && rule.chromiumFix {
                // One Shift+Left per character: output is precomposed Unicode only
                if backspaces > 0 {
                    plan.key(KeyCode.leftArrow, flags: .shift)
                    if backspaces == 1 { backspaces = 0 }
                }
            } else {
                plan.type(rule.emptyChar)
                plan.sleep(rule.delays.backspace)
                backspaces += 1
            }
        }

        // 2. Spotlight: select, then type over
        if spotlight && backspaces > 0 {
            selectForReplace(backspaces, rule: rule, clearInlineSuggestion: clearInlineSuggestion, into: &plan)
            backspaces = 0
        }

        // 3. Backspaces
        if backspaces > 0 && backspaces < maxBackspaces {
            for _ in 0..<backspaces {
                plan.key(KeyCode.delete)
                plan.sleep(rule.delays.backspace)
            }
            plan.sleep(rule.delays.beforeText)
        }

        // 4–5. Type the new text
        if preferences.sendKeyStepByStep {
            for ch in output.characters { typeOne(ch, into: &plan) }
            if let restore = output.restoreKey {
                if restore.unit == 0 { plan.repostOriginal() } else { typeOne(restore, into: &plan) }
            }
        } else {
            let textStart = plan.text.count
            for ch in output.characters where ch.unit != 0 { plan.append(ch.unit) }
            if let restore = output.restoreKey, restore.unit != 0 { plan.append(restore.unit) }
            plan.flushText(gap: rule.delays.text)
            // The steps so far stay as the fallback; the original key is reposted after either path
            if preferences.fixOverlayLauncher && context.axEdit && output.backspaces > 0 && output.backspaces < maxBackspaces {
                plan.axEdit = AXEdit(deleting: output.backspaces, textStart: textStart,
                                     textCount: plan.text.count - textStart, fallbackEnd: plan.steps.count)
            }
            if output.resendKey {
                if plan.hasText { plan.sleep(rule.delays.text) }
                plan.repostOriginal()
            }
        }
        plan.settle = rule.delays.settle
    }

    /// Spotlight replacement: select the `count` characters before the caret so the new text types over them.
    ///
    /// Spotlight may have auto-selected an inline suggestion after the caret ("ma" + selected "il"). Shift+Left
    /// would then shrink that selection instead of selecting "a", and a backspace would only remove the
    /// suggestion. Forward Delete removes it first. It would delete a real character if
    /// the caret were mid-text, hence `clearInlineSuggestion`.
    private static func selectForReplace(_ count: Int, rule: AppRule, clearInlineSuggestion: Bool,
                                         into plan: inout InjectionPlan) {
        if clearInlineSuggestion {
            plan.key(KeyCode.forwardDelete)
            plan.sleep(rule.delays.backspace)
        }
        for _ in 0..<count {
            plan.key(KeyCode.leftArrow, flags: .shift)
            plan.sleep(rule.delays.backspace)
        }
        plan.sleep(rule.delays.beforeText)
    }

    /// Macro expansion: empty char (ignoring `noEmptyCharPrefix` and the Chromium fix), backspaces (no
    /// 32 limit; selection in Spotlight), the expansion, then the trigger key re-sent by key code (with
    /// Shift if it was held).
    private static func planMacro(_ output: EngineOutput, context: AppContext, preferences: Preferences,
                                  clearInlineSuggestion: Bool, into plan: inout InjectionPlan) {
        var backspaces = output.backspaces
        let rule = context.rule
        if context.isSpotlight {
            if backspaces > 0 {
                selectForReplace(backspaces, rule: rule, clearInlineSuggestion: clearInlineSuggestion, into: &plan)
                backspaces = 0
            }
        } else if preferences.fixRecommendBrowser && rule.autocompleteFix {
            plan.type(rule.emptyChar)
            plan.sleep(rule.delays.backspace)
            backspaces += 1
        }
        if backspaces > 0 {
            for _ in 0..<backspaces {
                plan.key(KeyCode.delete)
                plan.sleep(rule.delays.backspace)
            }
            plan.sleep(rule.delays.beforeText)
        }
        if preferences.sendKeyStepByStep {
            for ch in output.characters { typeOne(ch, into: &plan) }
        } else {
            for ch in output.characters where ch.unit != 0 { plan.append(ch.unit) }
            plan.flushText(gap: rule.delays.text)
        }
        if let trigger = output.restoreKey, let keyCode = trigger.keyCode {
            if plan.hasText { plan.sleep(rule.delays.text) }
            plan.key(keyCode, flags: trigger.shifted ? [.shift, .nonCoalesced] : [.nonCoalesced])
        }
        plan.settle = rule.delays.settle
    }

    /// Send key by key: plain keys go out as key codes (with Shift), accented characters as Unicode,
    /// one event per character.
    private static func typeOne(_ ch: OutputCharacter, into plan: inout InjectionPlan) {
        if let keyCode = ch.keyCode {
            plan.key(keyCode, flags: ch.shifted ? [.shift, .nonCoalesced] : [.nonCoalesced])
        } else if ch.unit != 0 {
            plan.type(ch.unit)
        }
    }
}
