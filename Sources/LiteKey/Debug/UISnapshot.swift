#if DEBUG
import AppKit
import LiteKeyCore
import LiteKeyEngine
import SwiftUI

/// Debug builds only: the UI snapshot run behind `.github/workflows/ui-snapshots.yml`.
/// Renders the control panel (every tab, light and dark, a few special states), the macro window, the excluded
/// apps list and the menu bar menu to PNG files, clicks a few controls with real mouse events and writes
/// PASS/FAIL lines to `checks.txt`, then quits. Nothing here touches the user's settings.
///
///     LITEKEY_SNAPSHOT_DIR=/tmp/shots .build/debug/LiteKey   # from the repo root (for the app icon)
///
/// Each shot is saved twice: `<name>.png` from the window server (title bar and Liquid Glass included, 1x on
/// CI) and `<name>-2x.png` drawn from the view (Retina detail, but glass is not drawn).
final class UISnapshot: NSObject, NSApplicationDelegate {
    private struct Step {
        /// Screenshot taken after `delay`, if set
        var shot: String?
        var delay: Double = 1.5
        var action: () -> Void
    }

    private let dir: URL
    private let suite = "com.litekey.snapshot"
    private var window: NSWindow!
    private var model: ControlPanelModel!
    private var checks: [String] = []
    private var statusMenu: StatusMenu?

    init(dir: String) {
        self.dir = URL(fileURLWithPath: dir)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        if let icon = NSImage(contentsOfFile: "Resources/LiteKey.icns") { NSApp.applicationIconImage = icon }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        UserDefaults.standard.removePersistentDomain(forName: suite)
        model = ControlPanelModel(preferences: PreferencesModel(store: store))
        window = NSWindow.controlPanel(model: model, title: "LiteKey 1.0.2 - Bộ gõ Tiếng Việt")
        window.center()
        window.makeKeyAndOrderFront(nil)

        run((panelShots() + clickChecks() + otherWindows())[...]) { [unowned self] in
            try? checks.joined(separator: "\n").write(to: dir.appendingPathComponent("checks.txt"),
                                                      atomically: true, encoding: .utf8)
            captureMenu()
            NSApp.terminate(nil)
        }
    }

    private var store: PreferencesStore { PreferencesStore(defaults: UserDefaults(suiteName: suite)!) }
    private var prefs: PreferencesModel { model.preferences }

    private func show(_ appearance: NSAppearance.Name, _ tab: ControlPanelModel.Tab) {
        window.appearance = NSAppearance(named: appearance)
        model.tab = tab
    }

    // MARK: Control panel

    private func panelShots() -> [Step] {
        var steps: [Step] = []
        for (look, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            for tab in ControlPanelModel.Tab.allCases {
                steps.append(Step(shot: "\(look)-\(tab.rawValue)-\(tab)") { [unowned self] in
                    show(appearance, tab)
                    // The typing tab shows the missing-permission status, the others the running one
                    model.hasPermission = tab != .typing
                })
            }
        }
        // Dependent options disabled, unusable hotkey warning, permission banner: the tallest Bộ gõ page,
        // which must still fit without scrolling
        steps.append(Step(shot: "light-4-disabled") { [unowned self] in
            show(.aqua, .typing)
            model.hasPermission = false
            prefs.preferences.checkSpelling = false
            prefs.preferences.hotkey = Hotkey(modifiers: [], keyCode: KeyCode.z)
        })
        steps.append(Step(shot: "dark-5-disabled") { [unowned self] in
            show(.darkAqua, .shortcuts)
            prefs.preferences.useMacro = false
        })
        // Tab switch caught 0.1 s into the animation: both tabs should show, cross-fading (timing varies a little)
        steps.append(Step { [unowned self] in show(.darkAqua, .typing) })
        steps.append(Step(shot: "dark-7-crossfade", delay: 0.1) { [unowned self] in
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { model.tab = .system }
        })
        return steps
    }

    // MARK: Clicks

    /// Click positions are measured from the window's top-left corner on the macOS 27 screenshots
    /// (`light-0-typing.png`). If the layout moves, a check fails: update the coordinates here.
    private func clickChecks() -> [Step] {
        [
            Step(delay: 0.6) { [unowned self] in
                show(.aqua, .typing)
                prefs.preferences = Preferences()
                model.hasPermission = true
                // Clicks on a background window only activate it, so take focus back first
                NSApp.activate(ignoringOtherApps: true)
                window.makeKeyAndOrderFront(nil)
            },
            // A label click right after another label click waits 1 s: at 0.6 s the second click was
            // sometimes lost, close to the 0.5 s double-click interval
            Step(delay: 1.0) { [unowned self] in
                check("panel window is key before clicking", window.isKeyWindow)
                click(325, 383)  // label "Cho phép bỏ dấu tự do"
            },
            Step(delay: 0.6) { [unowned self] in
                check("click switch label turns it on", prefs.preferences.freeMark)
                click(325, 383)
            },
            Step(delay: 0.6) { [unowned self] in
                check("click switch label again turns it off", !prefs.preferences.freeMark)
                click(395, 131)  // ⌥ key
            },
            Step(delay: 0.6) { [unowned self] in
                check("click ⌥ key adds option", prefs.preferences.hotkey.modifiers.contains(.option))
                click(395, 131)
            },
            Step(delay: 0.6) { [unowned self] in
                check("click ⌥ key again removes option", !prefs.preferences.hotkey.modifiers.contains(.option))
                prefs.preferences.checkSpelling = false
            },
            Step(delay: 0.6) { [unowned self] in click(675, 323) },  // disabled label "Cho phép "z w j f""
            Step(delay: 0.6) { [unowned self] in
                check("click disabled label does nothing", !prefs.preferences.allowConsonantZFWJ)
                click(777, 131)  // label "Kêu beep"
            },
            Step(delay: 0.6) { [unowned self] in
                check("click \"Kêu beep\" label turns it on", prefs.preferences.beepOnSwitch)
                drag(402, 655, y: 97)  // Kiểu gõ: press on Telex, drag to Simple Telex 1
            },
            Step(delay: 0.6) { [unowned self] in
                // Only the macOS 26+ glass segments are ours; older versions use the native picker
                if LiquidGlass.isAvailable {
                    check("drag across Kiểu gõ selects the segment under the pointer",
                          prefs.preferences.inputType == .simpleTelex1)
                }
                click(75, 211)  // sidebar item "Gõ tắt"
            },
            Step(delay: 0.6) { [unowned self] in
                check("click tab selects it", model.tab == .shortcuts)
                model.tab = .system
            },
            Step(delay: 0.6) { [unowned self] in hover(320, 351) },  // row "Ứng dụng loại trừ..."
            Step(shot: "light-8-hover", delay: 0) {},
        ]
    }

    private func check(_ name: String, _ ok: Bool) {
        checks.append((ok ? "PASS " : "FAIL ") + name)
    }

    /// Window coordinates for a point measured from the window's top-left corner
    private func windowPoint(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
        NSPoint(x: x, y: window.frame.height - y)
    }

    private func mouseEvent(_ type: NSEvent.EventType, _ x: CGFloat, _ y: CGFloat) -> NSEvent? {
        NSEvent.mouseEvent(with: type, location: windowPoint(x, y), modifierFlags: [],
                           timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                           context: nil, eventNumber: 0, clickCount: 1, pressure: type == .leftMouseUp ? 0 : 1)
    }

    private func click(_ x: CGFloat, _ y: CGFloat) {
        guard let down = mouseEvent(.leftMouseDown, x, y), let up = mouseEvent(.leftMouseUp, x, y) else { return }
        // Queue the mouseUp first: controls that track the mouse (macOS 15) wait for it in the event queue
        NSApp.postEvent(up, atStart: false)
        window.sendEvent(down)
    }

    /// Press at `x0`, drag to `x1` and release there, on one row
    private func drag(_ x0: CGFloat, _ x1: CGFloat, y: CGFloat) {
        guard let down = mouseEvent(.leftMouseDown, x0, y), let moved = mouseEvent(.leftMouseDragged, x1, y),
              let up = mouseEvent(.leftMouseUp, x1, y) else { return }
        NSApp.postEvent(moved, atStart: false)
        NSApp.postEvent(up, atStart: false)
        window.sendEvent(down)
    }

    /// Moves the real cursor there so the window server's hover tracking fires
    private func hover(_ x: CGFloat, _ y: CGFloat) {
        let screenHeight = NSScreen.screens.first?.frame.height ?? 0
        let global = CGPoint(x: window.frame.minX + x, y: screenHeight - window.frame.maxY + y)
        CGWarpMouseCursorPosition(global)
        CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: global, mouseButton: .left)?
            .post(tap: .cghidEventTap)
    }

    // MARK: Macro window, excluded apps list

    private func otherWindows() -> [Step] {
        let macros = MacroModel(store: store)
        macros.table.add("vn", content: "Việt Nam")
        macros.table.add("ko", content: "không")
        let others: [(String, String, NSWindow)] = [
            ("macros", "Thiết lập gõ tắt",
             NSWindow(contentViewController: NSHostingController(rootView: MacroView(macros: macros, prefs: prefs)))),
            ("excluded", "Ứng dụng loại trừ",
             NSWindow(contentViewController: NSHostingController(rootView: ExcludedAppsView(prefs: prefs) {}))),
        ]
        var steps = [Step(delay: 0) { [unowned self] in
            prefs.preferences.excludedApps = ["com.apple.Terminal", "com.apple.Safari"]
        }]
        for (look, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            for (name, title, other) in others {
                steps.append(Step(shot: "\(look)-6-\(name)") { [unowned self] in
                    window.orderOut(nil)
                    others.forEach { $0.2.orderOut(nil) }
                    other.title = title
                    other.appearance = NSAppearance(named: appearance)
                    other.center()
                    other.makeKeyAndOrderFront(nil)
                    window = other
                })
            }
        }
        return steps
    }

    // MARK: Menu bar menu: item list in menu.txt, full-screen capture while it is open

    private func captureMenu() {
        window.orderOut(nil)
        var preferences = Preferences()
        preferences.excludedApps = ["com.apple.Terminal", "com.apple.Safari"]
        let owner = StatusMenu(actions: .init(
            toggleLanguage: {}, selectInputType: { _ in }, openControlPanel: {}, openMacros: {}, openAbout: {},
            openAccessibilitySettings: {}, frontApp: { "com.apple.Safari" }, toggleExcluded: { _ in },
            manageExcluded: {}, quit: {}))
        statusMenu = owner
        owner.refresh(preferences: preferences, hasPermission: true)
        guard let menu = owner.debugMenu() else { return }

        func dump(_ menu: NSMenu, _ indent: String) -> [String] {
            menu.items.flatMap { item -> [String] in
                let line = item.isSeparatorItem ? indent + "---"
                    : indent + (item.state == .on ? "✓ " : "  ") + item.title + (item.isEnabled ? "" : "  (disabled)")
                    + (item.toolTip.map { "  [\($0)]" } ?? "")
                return [line] + (item.submenu.map { dump($0, indent + "    ") } ?? [])
            }
        }
        try? dump(menu, "").joined(separator: "\n")
            .write(to: dir.appendingPathComponent("menu.txt"), atomically: true, encoding: .utf8)

        // popUp blocks while the menu is open: a timer in the tracking run loop mode takes the shot and closes it
        let timer = Timer(timeInterval: 1.0, repeats: false) { [unowned self] _ in
            screencapture(["-x", dir.appendingPathComponent("light-9-menu-screen.png").path])
            menu.cancelTracking()
        }
        RunLoop.main.add(timer, forMode: .common)
        menu.appearance = NSAppearance(named: .aqua)
        menu.popUp(positioning: nil, at: NSPoint(x: 200, y: (NSScreen.main?.frame.height ?? 800) - 60), in: nil)
    }

    // MARK: Running steps and saving shots

    private func run(_ steps: ArraySlice<Step>, then done: @escaping () -> Void) {
        guard let step = steps.first else {
            done()
            return
        }
        step.action()
        DispatchQueue.main.asyncAfter(deadline: .now() + step.delay) { [unowned self] in
            if let shot = step.shot { save(shot) }
            run(steps.dropFirst(), then: done)
        }
    }

    private func save(_ name: String) {
        screencapture(["-x", "-o", "-l", String(window.windowNumber), dir.appendingPathComponent("\(name).png").path])
        guard let view = window.contentView, let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(view.bounds.width * 2), pixelsHigh: Int(view.bounds.height * 2),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return }
        rep.size = view.bounds.size
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: dir.appendingPathComponent("\(name)-2x.png"))
    }

    private func screencapture(_ arguments: [String]) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        task.arguments = arguments
        try? task.run()
        task.waitUntilExit()
    }
}
#endif
