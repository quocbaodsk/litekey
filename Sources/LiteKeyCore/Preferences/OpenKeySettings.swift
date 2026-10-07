import LiteKeyEngine

/// Imports settings from OpenKey's preferences domain (`com.tuyenmai.openkey`).
///
/// The App layer reads OpenKey's integer keys from UserDefaults into `[String: Int]`; this pure function
/// maps them onto `Preferences`. Only keys that are present are applied. Options LiteKey lacks (code
/// tables, conversion, update checks) are ignored.
public enum OpenKeySettings {
    public static let domain = "com.tuyenmai.openkey"

    /// OpenKey integer keys LiteKey imports
    public static let keys = [
        "InputMethod", "InputType", "Spelling", "ModernOrthography", "QuickTelex", "RestoreIfInvalidWord",
        "FixRecommendBrowser", "SendKeyStepByStep", "UseSmartSwitchKey", "UpperCaseFirstChar", "FreeMark",
        "vTempOffSpelling", "vAllowConsonantZFWJ", "vQuickEndConsonant", "vQuickStartConsonant",
        "vOtherLanguage", "vTempOffOpenKey", "vShowIconOnDock", "vFixChromiumBrowser", "vPerformLayoutCompat",
        "SwitchKeyStatus", "GrayIcon", "ShowUIOnStartup",
        "UseMacro", "UseMacroInEnglishMode", "vAutoCapsMacro",
    ]

    public static func apply(_ values: [String: Int], to base: Preferences) -> Preferences {
        var p = base
        func flag(_ key: String, _ path: WritableKeyPath<Preferences, Bool>) {
            if let v = values[key] { p[keyPath: path] = v != 0 }
        }
        flag("InputMethod", \.vietnamese)
        if let v = values["InputType"], let type = InputType(rawValue: v) { p.inputType = type }
        flag("Spelling", \.checkSpelling)
        flag("ModernOrthography", \.modernOrthography)
        flag("QuickTelex", \.quickTelex)
        flag("RestoreIfInvalidWord", \.restoreIfWrong)
        flag("FixRecommendBrowser", \.fixRecommendBrowser)
        flag("SendKeyStepByStep", \.sendKeyStepByStep)
        flag("UseSmartSwitchKey", \.rememberPerApp)
        flag("UpperCaseFirstChar", \.upperCaseFirstChar)
        flag("FreeMark", \.freeMark)
        flag("vTempOffSpelling", \.tempOffSpellingWithControl)
        flag("vAllowConsonantZFWJ", \.allowConsonantZFWJ)
        flag("vQuickEndConsonant", \.quickEndConsonant)
        flag("vQuickStartConsonant", \.quickStartConsonant)
        flag("vOtherLanguage", \.disableOnNonEnglishInputSource)
        flag("vTempOffOpenKey", \.tempOffEngineWithCommand)
        flag("vShowIconOnDock", \.showIconOnDock)
        flag("vFixChromiumBrowser", \.fixChromiumBrowser)
        flag("vPerformLayoutCompat", \.layoutCompatibility)
        flag("GrayIcon", \.modernMenuIcon)
        flag("ShowUIOnStartup", \.showPanelOnStartup)
        flag("UseMacro", \.useMacro)
        flag("UseMacroInEnglishMode", \.useMacroInEnglishMode)
        flag("vAutoCapsMacro", \.autoCapsMacro)
        if let status = values["SwitchKeyStatus"] {
            let decoded = decodeSwitchKey(status)
            p.hotkey = decoded.hotkey
            p.beepOnSwitch = decoded.beep
        }
        return p
    }

    /// `SwitchKeyStatus`: low 8 bits are the key code (0xFE = none), bits 8–11 are ⌃ ⌥ ⌘ ⇧, bit 15 is beep
    public static func decodeSwitchKey(_ status: Int) -> (hotkey: Hotkey, beep: Bool) {
        var mods: ModifierFlags = []
        if status & 0x100 != 0 { mods.insert(.control) }
        if status & 0x200 != 0 { mods.insert(.option) }
        if status & 0x400 != 0 { mods.insert(.command) }
        if status & 0x800 != 0 { mods.insert(.shift) }
        let key = status & 0xFF
        return (Hotkey(modifiers: mods, keyCode: key == 0xFE ? nil : UInt16(key)), status & 0x8000 != 0)
    }

    public static func encodeSwitchKey(_ hotkey: Hotkey, beep: Bool) -> Int {
        var status = Int(hotkey.keyCode ?? 0xFE)
        if hotkey.modifiers.contains(.control) { status |= 0x100 }
        if hotkey.modifiers.contains(.option) { status |= 0x200 }
        if hotkey.modifiers.contains(.command) { status |= 0x400 }
        if hotkey.modifiers.contains(.shift) { status |= 0x800 }
        if beep { status |= 0x8000 }
        return status
    }
}
