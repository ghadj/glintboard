import Foundation

/// The store's own recent writes (path and content hash), so their FSEvents echoes aren't
/// mistaken for edits made elsewhere. An entry counts for 5 seconds; old entries are dropped
/// whenever a write is recorded, so there's no timer.
struct WriteLedger: Sendable {
    static let window: TimeInterval = 5

    private struct Entry: Sendable {
        let hash: String
        let time: Date
    }

    private var entries: [String: Entry] = [:]

    var count: Int { entries.count }

    /// Records a write. A later write to the same path replaces the earlier one: the file now
    /// holds the later content, so that's the echo to expect.
    mutating func record(path: String, hash: String, at time: Date) {
        entries = entries.filter { time.timeIntervalSince($0.value.time) < Self.window }
        entries[path] = Entry(hash: hash, time: time)
    }

    /// True if the file at `path` holds exactly what the store wrote there within the window.
    /// A matching entry stays, since one write can produce several FSEvents.
    func isEcho(path: String, hash: String, now: Date) -> Bool {
        guard let entry = entries[path] else { return false }
        return entry.hash == hash && now.timeIntervalSince(entry.time) < Self.window
    }
}
