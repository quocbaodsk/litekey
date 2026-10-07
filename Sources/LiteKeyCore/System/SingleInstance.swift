/// Keeps one LiteKey running at a time.
///
/// Two copies (an old build next to a new one, or a second copy launched from another folder) both
/// rewrite every word, so each diacritic is applied twice. The copy launched last takes over and asks the
/// older ones to quit: after an update, the new build is the one that keeps running.
public enum SingleInstance {
    public struct Copy: Equatable, Sendable {
        public var pid: Int32
        /// Launch time in seconds since 1970; `nil` when unknown
        public var launchedAt: Double?

        public init(pid: Int32, launchedAt: Double?) {
            self.pid = pid
            self.launchedAt = launchedAt
        }
    }

    /// The copies `own` should ask to quit: those launched before it. Equal times go by PID, so two copies
    /// started together never quit each other. An unknown launch time on either side quits nothing: each
    /// copy may see the other's time differently, and two copies beat none running.
    public static func olderCopies(than own: Copy, among others: [Copy]) -> [Int32] {
        guard let ownTime = own.launchedAt else { return [] }
        return others.filter { other in
            guard other.pid != own.pid, let otherTime = other.launchedAt else { return false }
            return otherTime < ownTime || (otherTime == ownTime && other.pid < own.pid)
        }.map(\.pid)
    }
}
