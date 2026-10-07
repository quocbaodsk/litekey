/// What the periodic tap watchdog should do.
public enum TapHealth {
    public enum Action: Equatable, Sendable {
        /// The tap is running normally
        case none
        /// macOS disabled the tap (timeout, sleep...) but permission remains: re-enable and start fresh
        case reenable
        /// Accessibility permission lost: remove the tap now so the keyboard does not lock up
        case stopForPermission
    }

    public static func check(tapInstalled: Bool, tapEnabled: Bool, trusted: Bool) -> Action {
        guard tapInstalled else { return .none }
        if !trusted { return .stopForPermission }
        return tapEnabled ? .none : .reenable
    }
}

/// What to do when macOS disables the tap (`tapDisabledByTimeout` / `tapDisabledByUserInput`).
///
/// Without permission the tap has to go right away: re-enabling it can lock up keyboard and mouse until
/// the process dies. `AXIsProcessTrusted()` can still say yes for a while after the permission is
/// revoked, so a burst of disables (`limit` within `window`) also drops the tap. Occasional disables
/// (Secure Input, a busy system) are simply re-enabled. `PermissionMonitor` is the main guard; this is
/// the backstop.
public struct TapDisableGuard: Sendable {
    public enum Action: Equatable, Sendable {
        case reenable
        case stop
    }

    public let limit: Int
    public let window: UInt64
    /// Timestamps (ns) of recent disables, at most `limit` entries
    private var times: [UInt64] = []

    public init(limit: Int = 5, window: UInt64 = 2_000_000_000) {
        self.limit = limit
        self.window = window
        times.reserveCapacity(limit)
    }

    public mutating func tapDisabled(at now: UInt64, trusted: Bool) -> Action {
        guard trusted else { return .stop }
        times.removeAll { now &- $0 > window }
        times.append(now)
        if times.count >= limit {
            times.removeAll(keepingCapacity: true)
            return .stop
        }
        return .reenable
    }

    /// The tap was recreated: forget earlier disables
    public mutating func reset() {
        times.removeAll(keepingCapacity: true)
    }
}

/// Secure Input state (password fields): while enabled, macOS sends no keys to event taps.
public struct SecureInputState: Equatable, Sendable {
    public var enabled: Bool
    /// Name of the app holding Secure Input, if known
    public var ownerName: String?

    public init(enabled: Bool = false, ownerName: String? = nil) {
        self.enabled = enabled
        self.ownerName = ownerName
    }

    /// Description line for the tooltip/menu
    public var message: String? {
        guard enabled else { return nil }
        if let ownerName { return "Đang nhập mật khẩu (Secure Input) trong \(ownerName): tạm thời không gõ tiếng Việt" }
        return "Đang nhập mật khẩu (Secure Input): tạm thời không gõ tiếng Việt"
    }
}
