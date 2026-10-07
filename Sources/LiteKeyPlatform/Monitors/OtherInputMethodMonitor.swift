import AppKit
import LiteKeyCore

/// Detects other Vietnamese input methods (OpenKey, XKey, EVKey...) running alongside LiteKey as apps
/// launch and quit. Runs on main, outside the tap callback.
public final class OtherInputMethodMonitor: NSObject {
    public private(set) var running: [String] = []
    /// The list changed (called on main)
    public var onChange: (([String]) -> Void)?

    public override init() {
        super.init()
        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(self, selector: #selector(appsChanged),
                       name: NSWorkspace.didLaunchApplicationNotification, object: nil)
        nc.addObserver(self, selector: #selector(appsChanged),
                       name: NSWorkspace.didTerminateApplicationNotification, object: nil)
        refresh()
    }

    deinit {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    @objc private func appsChanged() {
        refresh()
    }

    public func refresh() {
        let apps = NSWorkspace.shared.runningApplications.map { (bundleID: $0.bundleIdentifier, name: $0.localizedName) }
        let found = OtherInputMethods.running(apps, ownBundleID: Bundle.main.bundleIdentifier)
        guard found != running else { return }
        running = found
        onChange?(found)
    }
}
