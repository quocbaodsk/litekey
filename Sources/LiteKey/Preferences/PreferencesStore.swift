import Foundation
import LiteKeyCore
import LiteKeyEngine

/// Persists `Preferences` and the per-app mode table in UserDefaults.
struct PreferencesStore {
    let defaults: UserDefaults

    private static let preferencesKey = "Preferences"
    private static let appLanguageKey = "appLanguage"
    private static let macrosKey = "Macros"

    func load() -> Preferences {
        let stored: Preferences
        if let data = defaults.data(forKey: Self.preferencesKey),
           let prefs = try? JSONDecoder().decode(Preferences.self, from: data) {
            stored = prefs
        } else {
            stored = migrateLegacy()
        }
        let prefs = stored.migrated()
        if prefs != stored { save(prefs) }
        return prefs
    }

    func save(_ preferences: Preferences) {
        guard let data = try? JSONEncoder().encode(preferences) else { return }
        defaults.set(data, forKey: Self.preferencesKey)
    }

    func loadAppLanguages() -> PerAppLanguageStore {
        PerAppLanguageStore(languages: (defaults.dictionary(forKey: Self.appLanguageKey) as? [String: Bool]) ?? [:])
    }

    func save(_ store: PerAppLanguageStore) {
        defaults.set(store.languages, forKey: Self.appLanguageKey)
    }

    func loadMacros() -> MacroTable {
        guard let data = defaults.data(forKey: Self.macrosKey),
              let macros = try? JSONDecoder().decode([Macro].self, from: data) else { return MacroTable() }
        return MacroTable(macros: macros)
    }

    func save(_ macros: MacroTable) {
        guard let data = try? JSONEncoder().encode(macros.macros) else { return }
        defaults.set(data, forKey: Self.macrosKey)
    }

    /// Reads the legacy format (one UserDefaults key per option)
    private func migrateLegacy() -> Preferences {
        var p = Preferences()
        p.version = 1
        func bool(_ key: String, _ value: inout Bool) {
            if defaults.object(forKey: key) != nil { value = defaults.bool(forKey: key) }
        }
        bool("vietnamese", &p.vietnamese)
        bool("modernOrthography", &p.modernOrthography)
        bool("checkSpelling", &p.checkSpelling)
        bool("restoreIfWrong", &p.restoreIfWrong)
        bool("beepOnSwitch", &p.beepOnSwitch)
        bool("rememberPerApp", &p.rememberPerApp)
        if defaults.object(forKey: "inputType") != nil,
           let type = InputType(rawValue: defaults.integer(forKey: "inputType")) {
            p.inputType = type
        }
        switch defaults.string(forKey: "hotkey") {
        case "controlOption": p.hotkey = .controlOption
        case "controlSpace": p.hotkey = .controlSpace
        case "optionZ": p.hotkey = .optionZ
        default: break
        }
        p.excludedApps = defaults.stringArray(forKey: "excludedApps") ?? []
        return p
    }
}

/// The active macro table for SwiftUI. Every change is saved and forwarded to `onChange`.
final class MacroModel: ObservableObject {
    @Published var table: MacroTable {
        didSet {
            guard table != oldValue else { return }
            store.save(table)
            onChange?(table)
        }
    }

    var onChange: ((MacroTable) -> Void)?
    private let store: PreferencesStore

    init(store: PreferencesStore) {
        self.store = store
        self.table = store.loadMacros()
    }
}

/// The active preferences for SwiftUI. Every change is saved and forwarded to `onChange`.
final class PreferencesModel: ObservableObject {
    @Published var preferences: Preferences {
        didSet {
            guard preferences != oldValue else { return }
            store.save(preferences)
            onChange?(preferences)
        }
    }

    var onChange: ((Preferences) -> Void)?
    private let store: PreferencesStore

    init(store: PreferencesStore) {
        self.store = store
        self.preferences = store.load()
    }
}
