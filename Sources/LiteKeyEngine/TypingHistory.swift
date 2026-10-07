/// Word history entries stored back to back in one array. An array of arrays allocated a new array for every
/// saved word and space, inside the event tap callback; this copies into storage reserved up front.
struct TypingHistory {
    /// Entries back to back
    private var storage: [UInt32] = []
    /// End offset of each entry in `storage`
    private var ends: [Int] = []

    /// One extra entry because the engine appends before trimming. Best effort: long runs of spaces or
    /// punctuation are single entries longer than `elementsPerEntry` and grow `storage` once.
    init(entries: Int, elementsPerEntry: Int) {
        storage.reserveCapacity((entries + 1) * elementsPerEntry)
        ends.reserveCapacity(entries + 1)
    }

    var count: Int { ends.count }

    mutating func removeAll() {
        storage.removeAll(keepingCapacity: true)
        ends.removeAll(keepingCapacity: true)
    }

    mutating func append(_ entry: [UInt32]) {
        storage.append(contentsOf: entry)
        ends.append(storage.count)
    }

    /// Drops the `n` oldest entries
    mutating func removeFirst(_ n: Int) {
        guard n > 0 else { return }
        let cut = ends[n - 1]
        storage.removeFirst(cut)
        ends.removeFirst(n)
        var e = 0
        while e < ends.count {
            ends[e] -= cut
            e += 1
        }
    }

    /// Moves the newest entry into `entry`, replacing its contents
    mutating func removeLast(into entry: inout [UInt32]) {
        let end = ends.removeLast()
        let start = ends.last ?? 0
        entry.removeAll(keepingCapacity: true)
        entry.append(contentsOf: storage[start..<end])
        storage.removeLast(end - start)
    }
}
