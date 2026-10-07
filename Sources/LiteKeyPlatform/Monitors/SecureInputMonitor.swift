import AppKit
import Carbon
import LiteKeyCore

/// Monitors Secure Input (password fields, Terminal's "Secure Keyboard Entry"...). While it is on, macOS
/// does not deliver keys to event taps, so LiteKey cannot type Vietnamese; the state is shown on the icon.
/// Checked every 2 seconds on main (cheap) and whenever `refresh()` is called (app or field change).
public final class SecureInputMonitor {
    public private(set) var state = SecureInputState()
    /// The state changed (called on main)
    public var onChange: ((SecureInputState) -> Void)?
    private var timer: Timer?

    public init() {}

    public func start() {
        timer?.invalidate()
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in self?.refresh() }
        timer.tolerance = 0.5
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        refresh()
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
    }

    public func refresh() {
        var new = SecureInputState(enabled: IsSecureEventInputEnabled())
        if new.enabled {
            // Process holding Secure Input (private key, but stable across many macOS versions)
            if let session = CGSessionCopyCurrentDictionary() as? [String: Any],
               let pid = session["kCGSSessionSecureInputPID"] as? NSNumber {
                new.ownerName = NSRunningApplication(processIdentifier: pid.int32Value)?.localizedName
            }
        }
        guard new != state else { return }
        state = new
        onChange?(new)
    }
}
