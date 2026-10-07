import Foundation
import ApplicationServices

/// Watches the Accessibility permission.
///
/// Before it is granted we poll once a second on main. Once the tap runs we poll every 0.5 s on our own
/// queue (main may be busy) and also listen for `com.apple.accessibility.api`, because a tap left
/// enabled without permission can freeze keyboard and mouse.
public final class PermissionMonitor: NSObject {
    /// Permission was granted (after `waitForGrant`, called on main)
    public var onGranted: (() -> Void)?
    /// Permission was revoked; called right away on the background queue. Do only fast, thread-safe work
    /// (disable the tap).
    public var onRevokedImmediately: (() -> Void)?
    /// Permission was revoked (called on main after `onRevokedImmediately`); monitoring has already stopped
    public var onRevoked: (() -> Void)?

    private var grantTimer: Timer?
    private let queue = DispatchQueue(label: "LiteKey.PermissionMonitor", qos: .userInteractive)
    /// Touched only on `queue`
    private var revokeTimer: DispatchSourceTimer?

    public static var isTrusted: Bool { AXIsProcessTrusted() }

    public override init() {
        super.init()
        // macOS posts this whenever the Accessibility list changes (grant or revoke)
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(accessibilityListChanged),
            name: NSNotification.Name("com.apple.accessibility.api"), object: nil)
    }

    deinit {
        DistributedNotificationCenter.default().removeObserver(self)
        grantTimer?.invalidate()
        revokeTimer?.cancel()
    }

    /// Shows the system permission prompt
    public func prompt() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    public func waitForGrant() {
        grantTimer?.invalidate()
        grantTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
            guard AXIsProcessTrusted() else { return }
            timer.invalidate()
            self?.grantTimer = nil
            self?.onGranted?()
        }
    }

    public func watchForRevocation() {
        queue.async { [weak self] in
            guard let self else { return }
            self.revokeTimer?.cancel()
            let timer = DispatchSource.makeTimerSource(queue: self.queue)
            timer.schedule(deadline: .now() + 0.5, repeating: 0.5, leeway: .milliseconds(100))
            timer.setEventHandler { [weak self] in self?.checkRevoked() }
            self.revokeTimer = timer
            timer.resume()
        }
    }

    public func stopWatching() {
        queue.async { [weak self] in
            self?.revokeTimer?.cancel()
            self?.revokeTimer = nil
        }
    }

    @objc private func accessibilityListChanged() {
        queue.async { [weak self] in self?.checkRevoked() }
        // TCC may update after the notification is posted, so check again
        queue.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.checkRevoked() }
    }

    /// Runs on `queue`
    private func checkRevoked() {
        guard revokeTimer != nil, !AXIsProcessTrusted() else { return }
        revokeTimer?.cancel()
        revokeTimer = nil
        onRevokedImmediately?()
        DispatchQueue.main.async { [weak self] in self?.onRevoked?() }
    }
}
