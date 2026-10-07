/// One injection step. The macOS layer (`StepExecutor`) executes steps in order.
public enum InjectionStep: Equatable, Sendable {
    /// Press and release a virtual key
    case key(code: UInt16, flags: ModifierFlags)
    /// Type `plan.text[start ..< start + count]` in one Unicode event
    case text(start: Int, count: Int)
    /// Pause (intentional per-app delay)
    case sleep(microseconds: UInt32)
    /// Repost the original key (a copy of the received event)
    case repostOriginal
}

/// Experimental (`AppRule.axEdit`): the same replacement done through Accessibility instead of key events.
public struct AXEdit: Equatable, Sendable {
    /// UTF-16 units to delete before the caret
    public var deleting: Int
    /// Replacement text: `plan.text[textStart ..< textStart + textCount]`
    public var textStart: Int
    public var textCount: Int
    /// `steps[..<fallbackEnd]` make the same edit with key events: skipped when the AX edit succeeds, run
    /// when it fails. The steps after them always run.
    public var fallbackEnd: Int

    public init(deleting: Int, textStart: Int, textCount: Int, fallbackEnd: Int) {
        self.deleting = deleting
        self.textStart = textStart
        self.textCount = textCount
        self.fallbackEnd = fallbackEnd
    }

    /// The range to replace, from the field state read through AX (UTF-16 offsets): the `deleting` units
    /// before the caret plus any selection after it (an auto-selected inline suggestion). `nil` when the
    /// numbers are inconsistent or there are fewer units before the caret than we typed. Only counts are
    /// checked, not content: like the backspaces it replaces, it trusts the engine's view of the word.
    public static func replaceRange(caret: Int, selection: Int, total: Int?,
                                    deleting: Int) -> (location: Int, length: Int)? {
        guard deleting > 0, caret >= deleting, selection >= 0 else { return nil }
        if let total, caret + selection > total { return nil }
        return (caret - deleting, deleting + selection)
    }
}

/// The injection steps for one key press. Reused across keys (`reset()` keeps capacity) so the key
/// handling path does not allocate.
public struct InjectionPlan: Equatable, Sendable {
    public private(set) var steps: [InjectionStep] = []
    /// UTF-16 buffer referenced by `.text` steps
    public private(set) var text: [UInt16] = []
    /// Time (µs) the app needs to process this plan before the next real key is let through. Not a step:
    /// `SettleGate` only waits if the next key arrives earlier.
    public var settle: UInt32 = 0
    /// Set when the replacement may be done through Accessibility (`AppRule.axEdit`)
    public var axEdit: AXEdit?

    /// Maximum UTF-16 units per event
    public static let maxUnitsPerEvent = 16

    public init() {
        steps.reserveCapacity(64)
        text.reserveCapacity(64)
    }

    public var isEmpty: Bool { steps.isEmpty }

    public mutating func reset() {
        steps.removeAll(keepingCapacity: true)
        text.removeAll(keepingCapacity: true)
        settle = 0
        axEdit = nil
    }

    public mutating func key(_ code: UInt16, flags: ModifierFlags = [], times: Int = 1) {
        for _ in 0..<max(times, 0) { steps.append(.key(code: code, flags: flags)) }
    }

    public mutating func sleep(_ microseconds: UInt32) {
        if microseconds > 0 { steps.append(.sleep(microseconds: microseconds)) }
    }

    public mutating func repostOriginal() {
        steps.append(.repostOriginal)
    }

    /// Appends text to type, split into events of at most `maxUnitsPerEvent` units.
    public mutating func type<C: Collection>(_ units: C) where C.Element == UInt16 {
        var start = text.count
        text.append(contentsOf: units)
        while start < text.count {
            let count = chunk(from: start)
            steps.append(.text(start: start, count: count))
            start += count
        }
    }

    /// Units for the event starting at `start`. Never ends on the first half of a surrogate pair: an emoji
    /// split across two events (macro content) arrives as two invalid characters.
    private func chunk(from start: Int) -> Int {
        var count = min(Self.maxUnitsPerEvent, text.count - start)
        if start + count < text.count && UTF16.isLeadSurrogate(text[start + count - 1]) { count -= 1 }
        return count
    }

    public mutating func type(_ unit: UInt16) {
        type(CollectionOfOne(unit))
    }

    /// Appends one unit to the pending text; call `flushText()` to emit the `.text` steps.
    /// Use instead of `type` to build text unit by unit without a temporary array.
    public mutating func append(_ unit: UInt16) {
        text.append(unit)
    }

    /// Emits `.text` steps for appended text not yet covered by a step, pausing `gap` µs between
    /// consecutive events.
    public mutating func flushText(gap: UInt32 = 0) {
        let first = pendingStart
        var start = first
        while start < text.count {
            if start > first { sleep(gap) }
            let count = chunk(from: start)
            steps.append(.text(start: start, count: count))
            start += count
        }
    }

    /// Whether any text step exists
    public var hasText: Bool {
        steps.contains { if case .text = $0 { return true } else { return false } }
    }

    /// First index in `text` not covered by a `.text` step
    private var pendingStart: Int {
        for step in steps.reversed() {
            if case let .text(start, count) = step { return start + count }
        }
        return 0
    }
}
