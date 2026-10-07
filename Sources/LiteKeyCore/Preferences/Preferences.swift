import LiteKeyEngine

/// All user settings. `PreferencesStore` saves them; components get a copy on every change.
/// Missing keys decode to their defaults, so adding an option doesn't reset saved settings.
public struct Preferences: Codable, Equatable, Sendable {
    /// Format version; bump when old settings need migrating (see `migrated()`)
    public static let currentVersion = 3
    public var version = Preferences.currentVersion

    // MARK: Input
    public var vietnamese = true
    public var inputType: InputType = .telex
    /// Vietnamese/English switch hotkey; default ⌃⇧ (switches on key release)
    public var hotkey: Hotkey = .controlShift
    public var beepOnSwitch = false

    // MARK: Spelling and typing (passed to the engine)
    public var checkSpelling = true
    /// Restore the typed keys for invalid words
    public var restoreIfWrong = true
    /// Modern tone placement: oà, uý (instead of òa, úy)
    public var modernOrthography = false
    /// Allow placing tone marks anywhere in the word
    public var freeMark = false
    /// Quick Telex (cc=ch, gg=gi...)
    public var quickTelex = false
    /// Quick initial consonants (f→ph, j→gi, w→qu)
    public var quickStartConsonant = false
    /// Quick final consonants (g→ng, h→nh, k→ch)
    public var quickEndConsonant = false
    /// Allow "z w j f" as consonants
    public var allowConsonantZFWJ = false
    /// Capitalize the first letter of a sentence
    public var upperCaseFirstChar = false
    /// Pressing and releasing ⌃ turns spell checking off for the current word
    public var tempOffSpellingWithControl = false
    /// Pressing and releasing ⌘ turns the engine off for the current word
    public var tempOffEngineWithCommand = false

    // MARK: Macros
    public var useMacro = true
    /// Expand macros in English mode too
    public var useMacroInEnglishMode = false
    /// Match the macro expansion's case to the typed abbreviation
    public var autoCapsMacro = false

    // MARK: System
    /// Smart switching: remember Vietnamese/English per app
    public var rememberPerApp = true
    /// Turn off Vietnamese when the system input source is not English
    public var disableOnNonEnglishInputSource = true
    /// Autocomplete fix (browsers, Excel...): type an empty char before deleting
    public var fixRecommendBrowser = true
    /// Chromium fix: use Shift+Left instead of the empty char
    public var fixChromiumBrowser = false
    /// Send key by key (for apps that mishandle bulk text events)
    public var sendKeyStepByStep = false
    /// Telex compatibility on other layouts (Dvorak, Colemak...)
    public var layoutCompatibility = false
    public var showIconOnDock = false
    /// On by default so first-time users see the panel.
    public var showPanelOnStartup = true
    /// Modern monochrome menu bar icon
    public var modernMenuIcon = true
    /// Apps that always type English (bundle IDs)
    public var excludedApps: [String] = []

    public init() {}

    public var engineConfig: EngineConfig {
        EngineConfig(inputType: inputType,
                     modernOrthography: modernOrthography,
                     checkSpelling: checkSpelling,
                     restoreIfWrong: restoreIfWrong,
                     freeMark: freeMark,
                     quickTelex: quickTelex,
                     quickStartConsonant: quickStartConsonant,
                     quickEndConsonant: quickEndConsonant,
                     allowConsonantZFWJ: allowConsonantZFWJ,
                     upperCaseFirstChar: upperCaseFirstChar,
                     useMacro: useMacro,
                     autoCapsMacro: autoCapsMacro)
    }

    /// Reset-to-defaults button: reset settings, keeping the current mode and the excluded apps
    public func resetToDefaults() -> Preferences {
        var p = Preferences()
        p.vietnamese = vietnamese
        p.excludedApps = excludedApps
        return p
    }

    public func isExcluded(_ bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return excludedApps.contains(bundleID)
    }

    /// Menu bar shortcut: excludes the app, or removes it from the list if it is already there
    public func togglingExcluded(_ bundleID: String) -> Preferences {
        var p = self
        if p.excludedApps.contains(bundleID) {
            p.excludedApps.removeAll { $0 == bundleID }
        } else {
            p.excludedApps.append(bundleID)
        }
        return p
    }

    /// Migrates settings from older format versions.
    /// - v1 → v2: the default hotkey changed from ⌃⇧ to ⌥Z.
    /// - v2 → v3: the default hotkey changed back to ⌃⇧; settings still on the old ⌥Z default follow.
    public func migrated() -> Preferences {
        var p = self
        if p.version < 2 && p.hotkey == .controlShift {
            p.hotkey = .optionZ
        }
        if p.version < 3 && p.hotkey == .optionZ {
            p.hotkey = .controlShift
        }
        p.version = Preferences.currentVersion
        return p
    }

    private enum CodingKeys: String, CodingKey {
        case version, vietnamese, inputType, hotkey, beepOnSwitch
        case checkSpelling, restoreIfWrong, modernOrthography, freeMark, quickTelex
        case quickStartConsonant, quickEndConsonant, allowConsonantZFWJ, upperCaseFirstChar
        case tempOffSpellingWithControl, tempOffEngineWithCommand
        case useMacro, useMacroInEnglishMode, autoCapsMacro
        case rememberPerApp, disableOnNonEnglishInputSource, fixRecommendBrowser, fixChromiumBrowser
        case sendKeyStepByStep, layoutCompatibility, showIconOnDock, showPanelOnStartup, modernMenuIcon, excludedApps
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        var p = Preferences()
        func read<T: Decodable>(_ key: CodingKeys, _ value: inout T) {
            if let v = try? c.decodeIfPresent(T.self, forKey: key) { value = v }
        }
        // Settings without `version` are format v1
        p.version = 1
        read(.version, &p.version)
        read(.vietnamese, &p.vietnamese)
        read(.inputType, &p.inputType)
        read(.hotkey, &p.hotkey)
        read(.beepOnSwitch, &p.beepOnSwitch)
        read(.checkSpelling, &p.checkSpelling)
        read(.restoreIfWrong, &p.restoreIfWrong)
        read(.modernOrthography, &p.modernOrthography)
        read(.freeMark, &p.freeMark)
        read(.quickTelex, &p.quickTelex)
        read(.quickStartConsonant, &p.quickStartConsonant)
        read(.quickEndConsonant, &p.quickEndConsonant)
        read(.allowConsonantZFWJ, &p.allowConsonantZFWJ)
        read(.upperCaseFirstChar, &p.upperCaseFirstChar)
        read(.tempOffSpellingWithControl, &p.tempOffSpellingWithControl)
        read(.tempOffEngineWithCommand, &p.tempOffEngineWithCommand)
        read(.useMacro, &p.useMacro)
        read(.useMacroInEnglishMode, &p.useMacroInEnglishMode)
        read(.autoCapsMacro, &p.autoCapsMacro)
        read(.rememberPerApp, &p.rememberPerApp)
        read(.disableOnNonEnglishInputSource, &p.disableOnNonEnglishInputSource)
        read(.fixRecommendBrowser, &p.fixRecommendBrowser)
        read(.fixChromiumBrowser, &p.fixChromiumBrowser)
        read(.sendKeyStepByStep, &p.sendKeyStepByStep)
        read(.layoutCompatibility, &p.layoutCompatibility)
        read(.showIconOnDock, &p.showIconOnDock)
        read(.showPanelOnStartup, &p.showPanelOnStartup)
        read(.modernMenuIcon, &p.modernMenuIcon)
        read(.excludedApps, &p.excludedApps)
        self = p
    }
}
