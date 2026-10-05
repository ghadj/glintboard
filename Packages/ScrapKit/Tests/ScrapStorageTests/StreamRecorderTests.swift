import Foundation
import ScrapModel
import ScrapStorage
import ScrapTestSupport
import Testing

/// The recorder the FSEvents tests rely on: a wait must not succeed on a value that doesn't
/// match. An earlier version of these tests passed without checking anything (see the note on
/// `StreamRecorder`).
@Suite(.timeLimit(.minutes(1)))
struct StreamRecorderTests {
    private static func updated(at path: String) -> LibraryChange {
        .updated(IndexFixtures.scrap(), file: ScrapFileInfo(path: path, modified: IndexFixtures.created, size: 0))
    }

    @Test func waitReturnsNilWhenNothingMatches() async {
        let (stream, continuation) = AsyncStream<LibraryChange>.makeStream()
        let recorder = StreamRecorder(stream)
        continuation.yield(Self.updated(at: "Inbox/a.md"))
        let first = await recorder.waitFor(within: 5) { $0.path == "Inbox/a.md" }
        #expect(first?.path == "Inbox/a.md")

        let removed = await recorder.waitFor(within: 0.3) { $0 == .removed(path: "Inbox/a.md", id: nil) }
        #expect(removed == nil)
        let otherPath = await recorder.waitFor(within: 0.3) { $0.path == "Inbox/b.md" }
        #expect(otherPath == nil)
    }

    /// A value that doesn't match arrives during the wait, then one that does: the wait returns
    /// the second.
    @Test func waitSkipsNonMatchingValuesThatArriveLater() async {
        let (stream, continuation) = AsyncStream<LibraryChange>.makeStream()
        let recorder = StreamRecorder(stream)
        Task {
            continuation.yield(Self.updated(at: "Inbox/a.md"))
            try? await Task.sleep(for: .milliseconds(100))
            continuation.yield(.removed(path: "Inbox/a.md", id: nil))
        }
        let removed = await recorder.waitFor(within: 5) { $0 == .removed(path: "Inbox/a.md", id: nil) }
        #expect(removed == .removed(path: "Inbox/a.md", id: nil))
    }

    @Test func waitReturnsTheMatchingValueWhenItArrives() async {
        let (stream, continuation) = AsyncStream<LibraryChange>.makeStream()
        let recorder = StreamRecorder(stream)
        continuation.yield(Self.updated(at: "Inbox/a.md"))
        Task {
            continuation.yield(.removed(path: "Inbox/a.md", id: nil))
        }
        let removed = await recorder.waitFor(within: 5) { $0 == .removed(path: "Inbox/a.md", id: nil) }
        #expect(removed == .removed(path: "Inbox/a.md", id: nil))
    }
}
