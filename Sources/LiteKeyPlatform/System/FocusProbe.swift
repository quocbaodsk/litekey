import AppKit
import ApplicationServices
import LiteKeyCore

/// Where keystrokes are going, measured with Accessibility: whether Spotlight is focused, and the process
/// the experimental AX edit talks to.
public struct FocusInfo: Equatable, Sendable {
    /// App owning the focused element (differs from the frontmost app while Spotlight is open); `nil` on AX failure
    public var bundleID: String?
    /// Process owning the focused element; 0 on AX failure
    public var pid: Int32 = 0
    /// The Spotlight field (or Raycast/Alfred, `AppRules.isOverlayLauncher`) is receiving keys
    public var isSpotlight = false

    public init(bundleID: String? = nil, pid: Int32 = 0) {
        self.bundleID = bundleID
        self.pid = pid
        self.isSpotlight = AppRules.isOverlayLauncher(bundleID)
    }

    /// Apple's Spotlight specifically (inline suggestions; see `AppContext.spotlightSuggestions`)
    public var isAppleSpotlight: Bool { bundleID == AppRules.spotlight }
}

/// Tracks the frontmost app, the focused element (AX) and the user session.
///
/// Never call AX from the tap callback: each call is an IPC round trip that can take tens of ms.
/// FocusProbe runs AX on a background queue with a bounded timeout whenever Spotlight may have opened or
/// closed (app switch, modifier + Space; inside Spotlight also click, ⌘+key, Esc, Enter; see
/// `KeyEventProcessor.focusMayChange`). The callback only signals (`probeSoon`, non-blocking) and reads
/// the cached result from `AppContext`.
public final class FocusProbe: NSObject {
    public private(set) var frontBundleID: String?
    public private(set) var frontAppName: String?
    public private(set) var focus = FocusInfo()
    public private(set) var sessionOnConsole = true

    /// Another app was activated (LiteKey itself is ignored); called on main
    public var onFrontAppChanged: ((String?) -> Void)?
    /// The AX result changed; called on main
    public var onFocusChanged: ((FocusInfo) -> Void)?
    /// System or screen woke, screen unlocked, or session switched back: start a new word and check the tap
    public var onSessionReset: (() -> Void)?
    /// The user session left or returned to the console (Fast User Switching)
    public var onConsoleChanged: ((Bool) -> Void)?

    private let queue = DispatchQueue(label: "LiteKey.FocusProbe", qos: .userInitiated)
    private let systemWide = AXUIElementCreateSystemWide()
    /// Used only on `queue`
    private var generation = 0
    private var overlayPolling = false
    private var lastProbeWasOverlay = false
    private var lastOverlayBundleID: String?
    private var lastOverlayPID: Int32 = 0
    private var staleAnswers = 0

    /// Re-probe delays after a signal: a new window (Spotlight...) takes a moment to receive focus
    private static let chaseDelays: [Double] = [0.05, 0.15, 0.4]

    public override init() {
        let app = NSWorkspace.shared.frontmostApplication
        frontBundleID = app?.bundleIdentifier
        frontAppName = app?.localizedName
        super.init()
        // Keep a hung app from stalling FocusProbe (the system default is about 6 seconds)
        AXUIElementSetMessagingTimeout(systemWide, 0.25)
        if let session = CGSessionCopyCurrentDictionary() as? [String: Any],
           let onConsole = session[kCGSessionOnConsoleKey as String] as? Bool {
            sessionOnConsole = onConsole
        }
        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(self, selector: #selector(appActivated(_:)),
                       name: NSWorkspace.didActivateApplicationNotification, object: nil)
        nc.addObserver(self, selector: #selector(didWake),
                       name: NSWorkspace.didWakeNotification, object: nil)
        nc.addObserver(self, selector: #selector(sessionBecameActive),
                       name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)
        nc.addObserver(self, selector: #selector(sessionResigned),
                       name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
        nc.addObserver(self, selector: #selector(didWake),
                       name: NSWorkspace.screensDidWakeNotification, object: nil)
        // Screen unlock: the key recipient and modifier state may have changed
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(screenUnlocked),
            name: NSNotification.Name("com.apple.screenIsUnlocked"), object: nil)
    }

    deinit {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        DistributedNotificationCenter.default().removeObserver(self)
    }

    /// Re-probes the key recipient shortly. Safe from any thread (including the callback); returns immediately.
    public func probeSoon() {
        queue.async { [weak self] in self?.scheduleChase() }
    }

    // MARK: - Workspace

    @objc private func appActivated(_ note: Notification) {
        let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        let bundle = app?.bundleIdentifier
        guard bundle != Bundle.main.bundleIdentifier else { return }
        frontBundleID = bundle
        frontAppName = app?.localizedName
        onFrontAppChanged?(bundle)
        probeSoon()
    }

    @objc private func didWake() {
        onSessionReset?()
        probeSoon()
    }

    @objc private func screenUnlocked() {
        // Distributed notifications may arrive on another thread
        DispatchQueue.main.async { [weak self] in
            self?.onSessionReset?()
            self?.probeSoon()
        }
    }

    @objc private func sessionBecameActive() {
        sessionOnConsole = true
        onConsoleChanged?(true)
        onSessionReset?()
    }

    @objc private func sessionResigned() {
        sessionOnConsole = false
        onConsoleChanged?(false)
    }

    // MARK: - AX (runs only on `queue`)

    private func scheduleChase() {
        generation += 1
        let current = generation
        for delay in Self.chaseDelays {
            queue.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, self.generation == current else { return }
                self.probe()
            }
        }
    }

    /// One AX call: which process owns the focused element. We deliberately don't read roles or walk the
    /// tree, since frequent AX queries push Chrome/Electron (and VS Code) into their slower accessibility mode.
    private func probe() {
        var pid: pid_t = 0
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &value)
        if error == .success, let value, CFGetTypeID(value) == AXUIElementGetTypeID() {
            AXUIElementGetPid(value as! AXUIElement, &pid)
        }
        let bundle = pid > 0 ? NSRunningApplication(processIdentifier: pid)?.bundleIdentifier : nil
        var info = FocusInfo(bundleID: bundle, pid: bundle == nil ? 0 : pid)
        // A busy Spotlight can time out (cannotComplete): keep the last answer, at most twice in a row, instead
        // of reporting it closed, which would look like a freshly opened field on the next probe
        let transient = error == .cannotComplete || error == .failure
        if transient, lastProbeWasOverlay, staleAnswers < 2 {
            staleAnswers += 1
            info = FocusInfo(bundleID: lastOverlayBundleID, pid: lastOverlayPID)
        } else {
            staleAnswers = 0
            DispatchQueue.main.async { [weak self] in self?.publish(info) }
        }
        lastProbeWasOverlay = info.isSpotlight
        lastOverlayBundleID = info.isSpotlight ? info.bundleID : nil
        lastOverlayPID = info.isSpotlight ? info.pid : 0
        // Spotlight (like Raycast and Alfred) posts no notification when it closes, so poll while it is open
        if info.isSpotlight && !overlayPolling {
            overlayPolling = true
            queue.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.overlayPolling = false
                self?.probe()
            }
        }
    }

    private func publish(_ info: FocusInfo) {
        guard info != focus else { return }
        focus = info
        onFocusChanged?(info)
    }
}
