/// Finds other Vietnamese input methods running next to LiteKey.
///
/// Two of them rewriting the same word treat each other's injected backspaces as real keys, and letters
/// go missing in every app. LiteKey's own log looks fine when that happens, so we warn the user instead.
public enum OtherInputMethods {
    /// Known bundle IDs
    static let bundleIDs: Set<String> = [
        "com.tuyenmai.openkey",           // OpenKey
        "com.codetay.XKey",               // XKey
        "com.codetay.inputmethod.XKey",   // XKeyIM
        "com.trankynam.GoTiengViet",      // GõTiếngViệt
    ]

    /// Case-insensitive keywords in the app name or bundle ID, for input methods with unknown bundle IDs
    static let keywords = ["openkey", "xkey", "evkey", "gotiengviet", "unikey", "vietkey"]

    /// Names of other input methods among the running apps, skipping LiteKey itself (`ownBundleID`)
    public static func running(_ apps: [(bundleID: String?, name: String?)], ownBundleID: String?) -> [String] {
        var found: [String] = []
        for app in apps {
            if let id = app.bundleID, id == ownBundleID { continue }
            if matches(bundleID: app.bundleID, name: app.name) {
                let name = app.name ?? app.bundleID ?? "?"
                if !found.contains(name) { found.append(name) }
            }
        }
        return found
    }

    static func matches(bundleID: String?, name: String?) -> Bool {
        if let bundleID, bundleIDs.contains(bundleID) { return true }
        let haystack = ((bundleID ?? "") + " " + (name ?? "")).lowercased()
        return keywords.contains { haystack.contains($0) }
    }

    /// Warning line shown in the menu
    public static func message(_ names: [String]) -> String? {
        guard !names.isEmpty else { return nil }
        return "Đang chạy cùng bộ gõ khác: \(names.joined(separator: ", ")). Hãy thoát bộ gõ đó để không mất chữ"
    }
}
