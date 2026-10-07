/// Holds the next real key until the app has had `plan.settle` to process what we just injected.
/// Nothing sleeps after injecting; only a key that arrives too early waits for the rest.
public struct SettleGate: Sendable {
    /// Time (ns) the next key may pass; 0 = no wait
    private var readyAt: UInt64 = 0

    public init() {}

    /// A plan finished injecting at `now` (ns); the app needs `settle` µs to process it
    public mutating func injected(settle: UInt32, at now: UInt64) {
        readyAt = settle == 0 ? 0 : now &+ UInt64(settle) &* 1000
    }

    /// Microseconds to wait before handling an event arriving at `now`
    public func wait(at now: UInt64) -> UInt32 {
        guard now < readyAt else { return 0 }
        return UInt32(truncatingIfNeeded: (readyAt - now) / 1000)
    }

    /// Start over (the tap was recreated or re-enabled)
    public mutating func reset() {
        readyAt = 0
    }
}
