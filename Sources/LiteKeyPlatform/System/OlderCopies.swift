import AppKit
import LiteKeyCore

/// Asks older running copies of LiteKey to quit (see `SingleInstance`). Call once at launch, before the
/// event tap starts.
public enum OlderCopies {
    /// Returns the names of the copies asked to quit (for the log)
    @discardableResult
    public static func quit() -> [String] {
        guard let bundleID = Bundle.main.bundleIdentifier else { return [] }
        let me = NSRunningApplication.current
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        let older = SingleInstance.olderCopies(than: copy(me), among: running.map(copy))
        var names: [String] = []
        for app in running where older.contains(app.processIdentifier) {
            app.terminate()
            names.append(app.bundleURL?.path ?? "pid \(app.processIdentifier)")
        }
        return names
    }

    private static func copy(_ app: NSRunningApplication) -> SingleInstance.Copy {
        SingleInstance.Copy(pid: app.processIdentifier, launchedAt: app.launchDate?.timeIntervalSince1970)
    }
}
