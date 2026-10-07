/// Pauses between injected events, in microseconds. Most apps need none;
/// terminals and some IDEs drop keys that arrive back to back.
public struct InjectionDelays: Equatable, Sendable {
    /// After the empty-char prefix and after each backspace
    public var backspace: UInt32
    /// After the last backspace, before typing text
    public var beforeText: UInt32
    /// Between two text events (strings longer than 16 units, or before a reposted key)
    public var text: UInt32
    /// Time the app needs to process the injected keys. Not slept right after injecting: only a real key
    /// arriving earlier than that waits for the remainder (see `SettleGate`).
    public var settle: UInt32

    public init(backspace: UInt32, beforeText: UInt32, text: UInt32 = 0, settle: UInt32 = 0) {
        self.backspace = backspace
        self.beforeText = beforeText
        self.text = text
        self.settle = settle
    }

    public static let none = InjectionDelays(backspace: 0, beforeText: 0)
    /// Terminals, JetBrains IDEs (20 ms settle)
    public static let slow = InjectionDelays(backspace: 3000, beforeText: 6000, text: 3000, settle: 20000)
}

/// How keys are injected into a specific app. `AppRule.standard` (no pauses) applies to every app not
/// listed in `AppRules.builtIn`.
public struct AppRule: Equatable, Sendable {
    /// Empty char typed by the autocomplete fix: U+202F, or U+200C for Sublime Text
    public var emptyChar: UInt16 = 0x202F
    /// App gets the Chromium fix (exact bundle ID match)
    public var chromiumFix = false
    /// App may auto-select inline completions, so the autocomplete fix applies. Terminals have none: there
    /// it only cost an extra character, an extra backspace and their pauses on every key.
    public var autocompleteFix = true
    public var delays: InjectionDelays = .none
    /// Keys always go through untouched, as in an excluded app: remote desktop and VM clients forward keys
    /// to another machine, whose own input method types Vietnamese. Injected text arrives garbled there.
    public var passThrough = false

    public init(emptyChar: UInt16 = 0x202F, chromiumFix: Bool = false, autocompleteFix: Bool = true,
                delays: InjectionDelays = .none, passThrough: Bool = false) {
        self.emptyChar = emptyChar
        self.chromiumFix = chromiumFix
        self.autocompleteFix = autocompleteFix
        self.delays = delays
        self.passThrough = passThrough
    }

    public static let standard = AppRule()
}

/// Per-app rules as data: bundle ID → `AppRule`.
///
/// Looked up once per app switch (the result is cached in `AppContext`), never while handling a key.
public struct AppRules: Sendable {
    public var exact: [String: AppRule]
    /// Bundle ID prefix matches, checked in order
    public var prefixes: [(prefix: String, rule: AppRule)]
    public var fallback: AppRule
    /// Lowercased bundle IDs that get `AppRule.passThrough`, matched ignoring case since remote desktop
    /// vendors are inconsistent about case
    public var passThrough: Set<String>

    public init(exact: [String: AppRule], prefixes: [(prefix: String, rule: AppRule)] = [],
                fallback: AppRule = .standard, passThrough: Set<String> = []) {
        self.exact = exact
        self.prefixes = prefixes
        self.fallback = fallback
        self.passThrough = passThrough
    }

    public func rule(for bundleID: String?) -> AppRule {
        guard let bundleID else { return fallback }
        var rule = matchingRule(for: bundleID)
        if passThrough.contains(bundleID.lowercased()) { rule.passThrough = true }
        return rule
    }

    /// The app always types English: excluded by the user, or its rule passes keys through. Such apps also
    /// stay out of smart switching.
    public func alwaysEnglish(_ bundleID: String?, preferences: Preferences) -> Bool {
        preferences.isExcluded(bundleID) || rule(for: bundleID).passThrough
    }

    private func matchingRule(for bundleID: String) -> AppRule {
        if let rule = exact[bundleID] { return rule }
        for entry in prefixes where bundleID.hasPrefix(entry.prefix) {
            return entry.rule
        }
        return fallback
    }

    public static let spotlight = "com.apple.Spotlight"

    /// Launchers whose search field floats over the frontmost app (Spotlight, Raycast, Alfred). They get the
    /// Spotlight injection path. A switch, not a Set: called per key, so no hashing or lazy allocation.
    public static func isOverlayLauncher(_ bundleID: String?) -> Bool {
        switch bundleID {
        case spotlight?, "com.raycast.macos"?, "com.runningwithcrayons.Alfred"?: return true
        default: return false
        }
    }

    public static let builtIn: AppRules = {
        let base = AppRule()
        var table: [String: AppRule] = [:]
        for id in niceSpaceApps { table[id, default: base].emptyChar = 0x200C }
        for id in chromiumFixApps { table[id, default: base].chromiumFix = true }
        for id in slowApps { table[id, default: base].delays = .slow }
        for id in terminalApps {
            table[id, default: base].delays = .slow
            table[id, default: base].autocompleteFix = false
        }
        return AppRules(exact: table, prefixes: [("com.jetbrains.", AppRule(delays: .slow))], fallback: base,
                        passThrough: Set(passThroughApps.map { $0.lowercased() }))
    }()

    /// Apps that need U+200C as the empty char
    static let niceSpaceApps = ["com.sublimetext.2", "com.sublimetext.3", "com.sublimetext.4"]

    /// Chromium-based browsers that get the Chromium fix (exact bundle IDs only). Stable Edge is
    /// `com.microsoft.edgemac`.
    static let chromiumFixApps = [
        "com.google.Chrome", "com.google.Chrome.beta", "com.google.Chrome.dev", "com.google.Chrome.canary",
        "org.chromium.Chromium",
        "com.brave.Browser", "com.brave.Browser.beta", "com.brave.Browser.nightly",
        "com.microsoft.edgemac", "com.microsoft.edgemac.Beta", "com.microsoft.edgemac.Dev",
        "com.microsoft.edgemac.Canary",
        "com.vivaldi.Vivaldi", "com.operasoftware.Opera", "com.operasoftware.OperaGX",
        "company.thebrowser.Browser",
    ]

    /// Remote desktop and VM clients, and the iOS Simulator: the other side handles text input
    static let passThroughApps = [
        "com.p5sys.jump.mac.viewer", "com.microsoft.rdc.macos", "com.apple.remotedesktop",
        "com.carriez.rustdesk", "com.teamviewer.teamviewer", "com.philandro.anydesk",
        "com.parsecgaming.parsec", "com.moonlight-stream.moonlight", "com.zuler.deskin", "com.youqu.todesk",
        "com.oray.sunloginc", "com.splashtop.personal", "com.nomachine.nxplayer", "com.realvnc.vncviewer",
        "com.edovia.screens5", "com.citrix.receiver.nomas", "com.vmware.horizon", "com.vmware.fusion",
        "com.parallels.desktop.console", "com.apple.iphonesimulator",
    ]

    /// Apps that drop keys sent too fast but keep the autocomplete fix: editors with completions (JetBrains
    /// IDEs are matched by prefix), and Warp, whose own input editor suggests completions (not tested yet)
    static let slowApps = ["com.google.android.studio", "dev.warp.Warp-Stable"]

    /// Terminals: drop keys sent too fast, and have no inline autocomplete
    static let terminalApps = [
        "com.apple.Terminal", "com.googlecode.iterm2",
        "com.mitchellh.ghostty", "net.kovidgoyal.kitty", "io.alacritty",
        "com.github.wez.wezterm", "co.zeit.hyper", "org.tabby",
        "com.raphaelamorim.rio", "com.termius-dmg.mac", "com.cmuxterm.app",
    ]
}

/// What the key handler needs to know about the current key target. Computed outside the event tap
/// callback (on app switch, or when FocusProbe or the system input source reports a change); the callback
/// only reads it.
public struct AppContext: Equatable, Sendable {
    public var bundleID: String?
    public var rule: AppRule = .standard
    /// Keys pass through untouched (always English): see `excluded(by:)`
    public var isExcluded = false
    /// The Spotlight field (or another overlay launcher) has focus (checked via AX outside the callback)
    public var spotlightActive = false
    /// The overlay launcher with focus, while `spotlightActive`
    public var overlayBundleID: String?
    /// Apple's Spotlight field has focus, confirmed via AX: it may auto-select an inline suggestion after
    /// the caret. Raycast and Alfred windows also host notes and settings, so they never set this.
    public var spotlightSuggestions = false
    public var inputSourceIsEnglish = true
    /// Key remapping for non-US layout compatibility
    public var layoutMap = KeyboardLayoutMap()
    /// The user session is on the console (Fast User Switching)
    public var sessionOnConsole = true
    /// Suspend all processing (while recording the switch hotkey in the control panel)
    public var suspended = false

    public init(bundleID: String? = nil, rule: AppRule = .standard, isExcluded: Bool = false) {
        self.bundleID = bundleID
        self.rule = rule
        self.isExcluded = isExcluded
    }

    public init(bundleID: String?, rules: AppRules, preferences: Preferences) {
        self.init(bundleID: bundleID, rule: rules.rule(for: bundleID))
        isExcluded = excluded(by: preferences)
    }

    /// The app is in the exclusion list or its rule passes keys through. Once FocusProbe confirms an overlay
    /// launcher has focus, the launcher decides instead of the app under it: Spotlight opened over an
    /// excluded app still types Vietnamese, and an excluded Raycast stays English.
    public func excluded(by preferences: Preferences) -> Bool {
        if spotlightActive { return preferences.isExcluded(overlayBundleID) }
        return rule.passThrough || preferences.isExcluded(bundleID)
    }

    /// Typing into Spotlight, Raycast or Alfred: replace via selection instead of the empty-char prefix
    public var isSpotlight: Bool {
        spotlightActive || AppRules.isOverlayLauncher(bundleID)
    }
}
