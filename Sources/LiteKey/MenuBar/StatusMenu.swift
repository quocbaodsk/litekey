import AppKit
import LiteKeyCore
import LiteKeyEngine

/// The menu bar item and its menu. Left click opens the menu; ⌥-click toggles Vietnamese directly.
final class StatusMenu: NSObject {
    struct Actions {
        var toggleLanguage: () -> Void
        var selectInputType: (InputType) -> Void
        var openControlPanel: () -> Void
        var openMacros: () -> Void
        var openAbout: () -> Void
        var openAccessibilitySettings: () -> Void
        /// Bundle ID of the app the user was typing in (never LiteKey itself)
        var frontApp: () -> String?
        var toggleExcluded: (String) -> Void
        var manageExcluded: () -> Void
        var quit: () -> Void
    }

    /// Everything the icon and menu display
    private struct State: Equatable {
        var preferences: Preferences
        var hasPermission: Bool
        var secureInput: SecureInputState
        var otherInputMethods: [String]
    }

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let actions: Actions
    /// The displayed state; the menu is built from it when the user clicks the icon
    private var state: State?

    init(actions: Actions) {
        self.actions = actions
        super.init()
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(statusItemClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }

    /// Updates the icon. Runs on main, the same thread as the event tap, so it skips unchanged state and
    /// does not build the menu here (that happens on click).
    func refresh(preferences: Preferences, hasPermission: Bool, secureInput: SecureInputState = SecureInputState(),
                 otherInputMethods: [String] = []) {
        let new = State(preferences: preferences, hasPermission: hasPermission, secureInput: secureInput,
                        otherInputMethods: otherInputMethods)
        guard new != state else { return }
        state = new
        let conflict = OtherInputMethods.message(otherInputMethods)
        if let button = statusItem.button {
            let lock = secureInput.enabled
                ? NSImage(systemSymbolName: "lock.fill", accessibilityDescription: "Secure Input") : nil
            if !hasPermission {
                button.image = nil
                button.title = "⚠︎"
                button.imagePosition = .noImage
            } else if conflict != nil {
                // Another input method is running: both rewrite the same word and characters get lost
                button.image = nil
                button.title = (preferences.vietnamese ? "V" : "E") + "⚠︎"
                button.imagePosition = .noImage
            } else if let lock {
                // A password field holds the keyboard: LiteKey receives no keys
                lock.isTemplate = true
                button.image = lock
                button.title = preferences.vietnamese ? "V" : "E"
                button.imagePosition = .imageLeading
            } else if preferences.modernMenuIcon {
                button.title = ""
                button.image = MenuBarIcon.image(vietnamese: preferences.vietnamese)
                button.imagePosition = .imageOnly
            } else {
                button.image = nil
                button.title = preferences.vietnamese ? "V" : "E"
                button.imagePosition = .noImage
            }
            button.font = .systemFont(ofSize: 13, weight: .semibold)
            button.toolTip = conflict ?? secureInput.message ?? (hasPermission
                ? (preferences.vietnamese ? "LiteKey: Tiếng Việt" : "LiteKey: Tiếng Anh")
                : "LiteKey: chưa có quyền Trợ năng")
        }
    }

    private func makeMenu(_ state: State) -> NSMenu {
        let preferences = state.preferences
        let hasPermission = state.hasPermission
        let secureInput = state.secureInput
        let conflict = OtherInputMethods.message(state.otherInputMethods)
        let menu = NSMenu()
        menu.autoenablesItems = false
        if !hasPermission {
            menu.addItem(item("Cấp quyền Trợ năng…", #selector(openAccessibilitySettings)))
            menu.addItem(.separator())
        }
        if let conflict {
            let info = NSMenuItem(title: conflict, action: nil, keyEquivalent: "")
            info.isEnabled = false
            menu.addItem(info)
            menu.addItem(.separator())
        }
        if let message = secureInput.message {
            let info = NSMenuItem(title: message, action: nil, keyEquivalent: "")
            info.isEnabled = false
            menu.addItem(info)
            menu.addItem(.separator())
        }

        let vietnamese = item("Bật Tiếng Việt", #selector(toggleLanguage))
        vietnamese.state = preferences.vietnamese ? .on : .off
        if preferences.hotkey.isUsable, let keyCode = preferences.hotkey.keyCode {
            vietnamese.keyEquivalent = keyCode == KeyCode.space ? " " : KeyNames.name(for: keyCode).lowercased()
            vietnamese.keyEquivalentModifierMask = Self.menuModifiers(preferences.hotkey.modifiers)
        }
        menu.addItem(vietnamese)
        menu.addItem(.separator())

        let inputTypeItem = NSMenuItem(title: "Kiểu gõ", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        sub.autoenablesItems = false
        for (title, type) in [("Telex", InputType.telex), ("VNI", .vni),
                              ("Simple Telex 1", .simpleTelex1), ("Simple Telex 2", .simpleTelex2)] {
            let entry = item(title, #selector(selectInputType(_:)))
            entry.tag = type.rawValue
            entry.state = preferences.inputType == type ? .on : .off
            sub.addItem(entry)
        }
        inputTypeItem.submenu = sub
        menu.addItem(inputTypeItem)
        menu.addItem(.separator())

        addExcludedItems(to: menu, preferences: preferences)
        menu.addItem(.separator())

        menu.addItem(item("Bảng điều khiển...", #selector(openControlPanel)))
        menu.addItem(item("Gõ tắt...", #selector(openMacros)))
        menu.addItem(item("Giới thiệu", #selector(openAbout)))
        menu.addItem(.separator())
        menu.addItem(item("Thoát", #selector(quit), key: "q"))
        return menu
    }

    /// Quick exclusion: a checkable item for the current app, and a submenu of excluded apps (click one to remove it)
    private func addExcludedItems(to menu: NSMenu, preferences: Preferences) {
        if let bundle = actions.frontApp() {
            let current = item("Loại trừ “\(ExcludedAppsView.appName(bundle))”", #selector(toggleExcluded(_:)))
            current.representedObject = bundle
            current.state = preferences.isExcluded(bundle) ? .on : .off
            current.toolTip = "Luôn gõ tiếng Anh trong ứng dụng này"
            menu.addItem(current)
        } else {
            let current = NSMenuItem(title: "Loại trừ ứng dụng hiện tại", action: nil, keyEquivalent: "")
            current.isEnabled = false
            menu.addItem(current)
        }

        let listItem = NSMenuItem(title: "Ứng dụng loại trừ", action: nil, keyEquivalent: "")
        let list = NSMenu()
        list.autoenablesItems = false
        if preferences.excludedApps.isEmpty {
            let empty = NSMenuItem(title: "Chưa có ứng dụng nào", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            list.addItem(empty)
        }
        for bundle in preferences.excludedApps {
            let entry = item(ExcludedAppsView.appName(bundle), #selector(toggleExcluded(_:)))
            entry.representedObject = bundle
            entry.state = .on
            entry.toolTip = "Bấm để gỡ khỏi danh sách"
            list.addItem(entry)
        }
        list.addItem(.separator())
        list.addItem(item("Quản lý...", #selector(manageExcluded)))
        listItem.submenu = list
        menu.addItem(listItem)
    }

    @objc private func statusItemClicked() {
        if NSEvent.modifierFlags.contains(.option), NSApp.currentEvent?.type == .leftMouseUp {
            actions.toggleLanguage()
            return
        }
        guard let state else { return }
        // Attach the menu temporarily so it opens under the icon, then detach it so later clicks still arrive
        statusItem.menu = makeMenu(state)
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    private static func menuModifiers(_ mods: ModifierFlags) -> NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if mods.contains(.control) { flags.insert(.control) }
        if mods.contains(.option) { flags.insert(.option) }
        if mods.contains(.command) { flags.insert(.command) }
        if mods.contains(.shift) { flags.insert(.shift) }
        return flags
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc private func toggleLanguage() { actions.toggleLanguage() }
    @objc private func selectInputType(_ sender: NSMenuItem) {
        if let type = InputType(rawValue: sender.tag) { actions.selectInputType(type) }
    }
    @objc private func openControlPanel() { actions.openControlPanel() }
    @objc private func openMacros() { actions.openMacros() }
    @objc private func openAbout() { actions.openAbout() }
    @objc private func openAccessibilitySettings() { actions.openAccessibilitySettings() }
    @objc private func toggleExcluded(_ sender: NSMenuItem) {
        if let bundle = sender.representedObject as? String { actions.toggleExcluded(bundle) }
    }
    @objc private func manageExcluded() { actions.manageExcluded() }
    @objc private func quit() { actions.quit() }
}

#if DEBUG
extension StatusMenu {
    /// UI snapshot run: the menu as it would open now
    func debugMenu() -> NSMenu? { state.map(makeMenu) }
}
#endif
