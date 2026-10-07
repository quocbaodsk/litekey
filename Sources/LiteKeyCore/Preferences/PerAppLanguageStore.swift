/// Remembers Vietnamese/English mode per app (logic only; the App layer persists it).
public struct PerAppLanguageStore: Codable, Equatable, Sendable {
    /// bundle ID → true (Vietnamese) / false (English)
    public private(set) var languages: [String: Bool]

    public init(languages: [String: Bool] = [:]) {
        self.languages = languages
    }

    public func language(for bundleID: String) -> Bool? {
        languages[bundleID]
    }

    public mutating func remember(_ vietnamese: Bool, for bundleID: String?) {
        guard let bundleID else { return }
        languages[bundleID] = vietnamese
    }

    /// Call when an app is activated. Returns the mode to switch to, if it differs from the current one;
    /// an app seen for the first time remembers the current mode. Excluded apps always type English, so
    /// they neither change nor record the mode.
    public mutating func activate(_ bundleID: String, current vietnamese: Bool, excluded: Bool = false) -> Bool? {
        guard !excluded else { return nil }
        if let remembered = languages[bundleID] {
            return remembered != vietnamese ? remembered : nil
        }
        languages[bundleID] = vietnamese
        return nil
    }

    public mutating func forgetAll() {
        languages.removeAll()
    }
}
