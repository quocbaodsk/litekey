import AppKit
import LiteKeyCore
import LiteKeyEngine
import LiteKeyPlatform
import SwiftUI

/// Composition root: assembles every component and wires events between them.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = PreferencesStore(defaults: .standard)
    private lazy var model = PreferencesModel(store: store)
    private lazy var panelModel = ControlPanelModel(preferences: model)
    private lazy var macroModel = MacroModel(store: store)
    private var macroWindow: NSWindow?
    private lazy var appLanguages = store.loadAppLanguages()
    private let rules = AppRules.builtIn
    private let permission = PermissionMonitor()
    private let focus = FocusProbe()
    private let inputSource = InputSourceMonitor()
    private let secureInput = SecureInputMonitor()
    private let otherInputMethods = OtherInputMethodMonitor()
    private var diagnostics: Diagnostics!
    private var watchdog: Timer?
    private var pipeline: KeyboardPipeline<VietnameseEngine>!
    private var statusMenu: StatusMenu!
    private var panelWindow: NSWindow?
    private var permissionWindow: NSWindow?
    private var recordingHotkey = false
    /// Consecutive times the tap was removed because macOS kept disabling it (drives retry backoff)
    private var gaveUpCount = 0
    /// When the tap was last created; once it has run stably long enough, earlier removals are forgotten
    private var tapStartedAt = Date.distantPast

    private var preferences: Preferences {
        get { model.preferences }
        set { model.preferences = newValue }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let prefs = model.preferences
        diagnostics = Diagnostics(subsystem: Bundle.main.bundleIdentifier ?? "com.litekey.app",
                                      enabled: UserDefaults.standard.bool(forKey: Diagnostics.defaultsKey))
        // Before the tap starts: two copies would both rewrite every word
        diagnostics.olderCopiesQuit(OlderCopies.quit())
        // Experimental AX edit: on unless turned off for comparison
        let axEdit = UserDefaults.standard.object(forKey: AXTextEditor.defaultsKey) == nil
            || UserDefaults.standard.bool(forKey: AXTextEditor.defaultsKey)
        pipeline = KeyboardPipeline(engine: VietnameseEngine(config: prefs.engineConfig),
                                    preferences: prefs,
                                    context: currentContext(),
                                    diagnostics: diagnostics,
                                    axEdit: axEdit)
        diagnostics.note("Experimental AX edit: \(axEdit ? "on" : "off")")
        pipeline.update(macros: macroModel.table)
        macroModel.onChange = { [weak self] table in self?.pipeline.update(macros: table) }
        pipeline.onLanguageToggled = { [weak self] vietnamese in self?.languageToggledByHotkey(vietnamese) }
        pipeline.onPermissionLost = { [weak self] in self?.permissionLost() }
        pipeline.onGaveUp = { [weak self] in self?.tapGaveUp() }
        // Permission loss is detected on a background queue: disable the tap right there instead of waiting
        // for a possibly busy main thread
        permission.onRevokedImmediately = { [pipeline = self.pipeline!] in pipeline.disableNow() }
        pipeline.onFocusHint = { [focus = self.focus] in focus.probeSoon() }

        statusMenu = StatusMenu(actions: .init(
            toggleLanguage: { [weak self] in self?.toggleLanguage() },
            selectInputType: { [weak self] type in self?.preferences.inputType = type },
            openControlPanel: { [weak self] in self?.openControlPanel(tab: .typing) },
            openMacros: { [weak self] in self?.openMacroWindow() },
            openAbout: { [weak self] in self?.openControlPanel(tab: .info) },
            openAccessibilitySettings: { Self.openAccessibilitySettings() },
            frontApp: { [weak self] in self?.focus.frontBundleID },
            toggleExcluded: { [weak self] bundle in
                guard let self else { return }
                self.preferences = self.preferences.togglingExcluded(bundle)
            },
            manageExcluded: { [weak self] in
                self?.openControlPanel(tab: .system)
                self?.panelModel.showExcludedApps = true
            },
            quit: { [weak self] in self?.quit() }
        ))

        panelModel.onRetryPermission = { [weak self] in self?.retryPermission() }
        panelModel.onRecordingHotkey = { [weak self] recording in
            self?.recordingHotkey = recording
            self?.pushContext()
        }
        panelModel.onQuit = { [weak self] in self?.quit() }
        panelModel.onClose = { [weak self] in self?.panelWindow?.close() }
        panelModel.canImportOpenKey = { !Self.readOpenKeySettings().isEmpty }
        panelModel.onImportOpenKey = { [weak self] in self?.importOpenKeySettings() }
        panelModel.onOpenMacros = { [weak self] in self?.openMacroWindow() }

        model.onChange = { [weak self] prefs in
            guard let self else { return }
            self.pipeline.update(preferences: prefs)
            self.pushContext()
            self.applyDockIcon()
            self.refreshMenu()
        }
        focus.onFrontAppChanged = { [weak self] bundle in self?.frontAppChanged(bundle) }
        focus.onFocusChanged = { [weak self] _ in
            self?.pushContext()
            self?.secureInput.refresh()
        }
        focus.onConsoleChanged = { [weak self] _ in self?.pushContext() }
        focus.onSessionReset = { [weak self] in
            self?.pipeline.newSession()
            self?.checkTapHealth()
        }
        secureInput.onChange = { [weak self] _ in self?.refreshMenu() }
        otherInputMethods.onChange = { [weak self] names in
            self?.diagnostics.otherInputMethods(names)
            self?.refreshMenu()
        }
        diagnostics.otherInputMethods(otherInputMethods.running)
        inputSource.onChange = { [weak self] in
            guard let self else { return }
            self.diagnostics.note("System input source changed: english=\(self.inputSource.isEnglish)")
            self.pushContext()
        }
        permission.onGranted = { [weak self] in
            self?.gaveUpCount = 0
            self?.startTap()
        }
        permission.onRevoked = { [weak self] in self?.permissionLost() }

        applyDockIcon()
        if PermissionMonitor.isTrusted {
            startTap()
        } else {
            showPermissionWindow()
            // Prompt right away so LiteKey already appears in the Accessibility list
            permission.prompt()
            permission.waitForGrant()
        }
        refreshMenu()
        if preferences.showPanelOnStartup {
            openControlPanel(tab: .typing)
        }
    }

    /// Reopening the app (clicking the Dock icon) shows the Control Panel
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openControlPanel(tab: .typing)
        return true
    }

    // MARK: - Accessibility permission

    private func startTap() {
        if pipeline.start() {
            tapStartedAt = Date()
            permission.watchForRevocation()
            startWatchdog()
            secureInput.start()
            focus.probeSoon()
            permissionWindow?.close()
            permissionWindow = nil
        } else {
            // Trusted but the tap could not be created yet (common right after granting); retry
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.startTap() }
        }
        refreshMenu()
    }

    private func retryPermission() {
        if PermissionMonitor.isTrusted {
            startTap()
        } else {
            permission.prompt()
            permission.waitForGrant()
        }
    }

    /// Removes the stale LiteKey entry from Accessibility (older ad-hoc signed build) and asks again.
    /// Only done while the tap is not running, so changing permission cannot freeze the keyboard.
    private func resetPermission() {
        guard !pipeline.isRunning, let bundleID = Bundle.main.bundleIdentifier else { return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
            task.arguments = ["reset", "Accessibility", bundleID]
            try? task.run()
            task.waitUntilExit()
            DispatchQueue.main.async {
                guard let self else { return }
                self.permission.prompt()
                self.permission.waitForGrant()
                Self.openAccessibilitySettings()
            }
        }
    }

    private static func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    /// Watchdog: every 5 seconds checks that the tap is still enabled and re-enables it if macOS disabled it
    private func startWatchdog() {
        watchdog?.invalidate()
        let timer = Timer(timeInterval: 5, repeats: true) { [weak self] _ in self?.checkTapHealth() }
        timer.tolerance = 1
        RunLoop.main.add(timer, forMode: .common)
        watchdog = timer
    }

    private func checkTapHealth() {
        guard pipeline.isRunning else { return }
        if pipeline.checkHealth(trusted: PermissionMonitor.isTrusted) == .stopForPermission {
            permissionLost()
        }
    }

    private func permissionLost() {
        watchdog?.invalidate()
        watchdog = nil
        secureInput.stop()
        permission.stopWatching()
        pipeline.stop()
        permission.waitForGrant()
        refreshMenu()
    }

    /// macOS kept disabling the tap, so it was removed to avoid hanging the keyboard. Retry with backoff
    /// (1 s, 3 s, 10 s, then every 30 s); if permission is really gone, wait for the grant as usual.
    /// If the tap had run stably for over a minute, this removal counts as the first.
    private func tapGaveUp() {
        if Date().timeIntervalSince(tapStartedAt) > 60 { gaveUpCount = 0 }
        watchdog?.invalidate()
        watchdog = nil
        secureInput.stop()
        permission.stopWatching()
        pipeline.stop()
        refreshMenu()
        let delays: [Double] = [1, 3, 10, 30]
        let delay = delays[min(gaveUpCount, delays.count - 1)]
        gaveUpCount += 1
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, !self.pipeline.isRunning else { return }
            if PermissionMonitor.isTrusted {
                self.startTap()
            } else {
                self.permission.waitForGrant()
            }
        }
    }

    private func showPermissionWindow() {
        if permissionWindow == nil {
            let view = PermissionView(model: PermissionModel(),
                                      onOpenSettings: { Self.openAccessibilitySettings() },
                                      onReset: { [weak self] in self?.resetPermission() },
                                      onRetry: { [weak self] in self?.retryPermission() })
            let window = NSWindow(contentViewController: NSHostingController(rootView: view))
            window.title = "LiteKey"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            permissionWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        permissionWindow?.makeKeyAndOrderFront(nil)
    }

    // MARK: - Vietnamese/English switching

    private func toggleLanguage() {
        preferences.vietnamese.toggle()
        languageChanged()
    }

    /// The hotkey already toggled the mode in the pipeline; sync preferences and UI
    private func languageToggledByHotkey(_ vietnamese: Bool) {
        preferences.vietnamese = vietnamese
        languageChanged()
    }

    /// Beeps and remembers the mode for the current app
    private func languageChanged() {
        if preferences.beepOnSwitch { NSSound.beep() }
        if preferences.rememberPerApp, let bundle = focus.frontBundleID,
           !rules.alwaysEnglish(bundle, preferences: preferences) {
            appLanguages.remember(preferences.vietnamese, for: bundle)
            store.save(appLanguages)
        }
    }

    /// Smart switching: restores the mode remembered for the newly active app
    private func frontAppChanged(_ bundle: String?) {
        pushContext()
        guard preferences.rememberPerApp, let bundle else { return }
        let before = appLanguages
        if let target = appLanguages.activate(bundle, current: preferences.vietnamese,
                                              excluded: rules.alwaysEnglish(bundle, preferences: preferences)) {
            // `model.onChange` saves preferences and redraws the menu
            preferences.vietnamese = target
        }
        // The user is about to type after an app switch (the tap runs on main): write UserDefaults only for a new app
        if appLanguages != before { store.save(appLanguages) }
    }

    // MARK: - Typing context

    /// Collects everything measured outside the callback into an `AppContext` for the pipeline
    private func currentContext() -> AppContext {
        var ctx = AppContext(bundleID: focus.frontBundleID, rules: rules, preferences: preferences)
        ctx.spotlightActive = focus.focus.isSpotlight
        ctx.overlayBundleID = focus.focus.isSpotlight ? focus.focus.bundleID : nil
        ctx.spotlightSuggestions = focus.focus.isAppleSpotlight
        ctx.overlayAXEdit = focus.focus.isSpotlight && rules.rule(for: focus.focus.bundleID).axEdit
        ctx.focusedPID = focus.focus.pid
        ctx.inputSourceIsEnglish = inputSource.isEnglish
        ctx.layoutMap = inputSource.layoutMap
        ctx.sessionOnConsole = focus.sessionOnConsole
        ctx.suspended = recordingHotkey
        return ctx
    }

    private func pushContext() {
        pipeline.update(context: currentContext())
    }

    // MARK: - Import settings from OpenKey

    /// Reads OpenKey's integer keys (domain com.tuyenmai.openkey), if present
    private static func readOpenKeySettings() -> [String: Int] {
        var values: [String: Int] = [:]
        for key in OpenKeySettings.keys {
            if let value = CFPreferencesCopyAppValue(key as CFString, OpenKeySettings.domain as CFString) as? NSNumber {
                values[key] = value.intValue
            }
        }
        return values
    }

    private func importOpenKeySettings() {
        let values = Self.readOpenKeySettings()
        guard !values.isEmpty else { return }
        preferences = OpenKeySettings.apply(values, to: preferences)
        // Macros (binary "macroData"): merge in, keeping existing entries
        if let data = CFPreferencesCopyAppValue("macroData" as CFString, OpenKeySettings.domain as CFString) as? Data {
            var table = macroModel.table
            for macro in MacroTable(openKeyData: [UInt8](data)).macros where !table.has(macro.text) {
                table.add(macro.text, content: macro.content)
            }
            macroModel.table = table
        }
    }

    // MARK: - Menu, Dock, windows

    private func refreshMenu() {
        statusMenu.refresh(preferences: preferences, hasPermission: pipeline.isRunning, secureInput: secureInput.state,
                           otherInputMethods: otherInputMethods.running)
        panelModel.hasPermission = pipeline.isRunning
    }

    private func applyDockIcon() {
        let policy: NSApplication.ActivationPolicy = preferences.showIconOnDock ? .regular : .accessory
        if NSApp.activationPolicy() != policy { NSApp.setActivationPolicy(policy) }
    }

    private func openControlPanel(tab: ControlPanelModel.Tab) {
        panelModel.tab = tab
        panelModel.launchAtLogin = LoginItem.isEnabled
        panelModel.hasPermission = pipeline.isRunning
        if panelWindow == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: ControlPanelView(model: panelModel)))
            let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
            window.title = "LiteKey \(version) - Bộ gõ Tiếng Việt"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.center()
            panelWindow = window
            // Safety net: closing the Control Panel always ends any hotkey-recording suspension
            NotificationCenter.default.addObserver(self, selector: #selector(panelWillClose(_:)),
                                                   name: NSWindow.willCloseNotification, object: window)
        }
        NSApp.activate(ignoringOtherApps: true)
        panelWindow?.makeKeyAndOrderFront(nil)
    }

    @objc private func panelWillClose(_ note: Notification) {
        guard recordingHotkey else { return }
        recordingHotkey = false
        pushContext()
    }

    private func openMacroWindow() {
        if macroWindow == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: MacroView(macros: macroModel, prefs: model)))
            window.title = "Thiết lập gõ tắt"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.isReleasedWhenClosed = false
            window.center()
            macroWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        macroWindow?.makeKeyAndOrderFront(nil)
    }

    private func quit() {
        pipeline.stop()
        NSApp.terminate(nil)
    }
}
