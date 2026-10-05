import CoreServices
import Foundation
import ScrapTestSupport
import Testing

@testable import ScrapStorage

@Suite(.timeLimit(.minutes(1)))
struct FolderWatcherTests {
    /// The temporary folder lives under `/var`, a link to `/private/var`. FSEvents reports the
    /// resolved path, so a watcher given the unresolved one must still report paths relative to
    /// its root.
    @Test func reportsPathsRelativeToSymlinkedRoot() async throws {
        let library = try TemporaryLibrary()
        let resolved = library.base.path(percentEncoded: false)
        try #require(resolved.hasPrefix("/private/var/"), "needs a temporary folder under /var")
        let throughLink = URL(filePath: String(resolved.dropFirst("/private".count)), directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: library.base.appending(path: "Inbox"), withIntermediateDirectories: true)

        let watcher = FolderWatcher(root: throughLink)
        let batches = try await watcher.start()
        // One event per value, so the wait below can match on the path alone (see the note on
        // `StreamRecorder`).
        let events = StreamRecorder(
            AsyncStream<FolderEvent> { continuation in
                let forward = Task {
                    for await batch in batches { for event in batch { continuation.yield(event) } }
                    continuation.finish()
                }
                continuation.onTermination = { _ in forward.cancel() }
            })
        try Data("x".utf8).write(to: library.base.appending(path: "Inbox/x.md"))

        let event = await events.waitFor(within: 10) { $0.path == "Inbox/x.md" }
        await watcher.stop()
        #expect(event?.path == "Inbox/x.md")
    }

    // MARK: - Mapping FSEvents flags (no FSEvents needed)

    private let watcher = FolderWatcher(root: URL(filePath: "/nonexistent/Library", directoryHint: .isDirectory))

    private func flags(_ values: Int...) -> FSEventStreamEventFlags {
        FSEventStreamEventFlags(values.reduce(0, |))
    }

    @Test func pathsAreRelativeToTheRoot() {
        let file = flags(kFSEventStreamEventFlagItemIsFile, kFSEventStreamEventFlagItemModified)
        #expect(watcher.event(path: "/nonexistent/Library/Inbox/a.md", flags: file)?.path == "Inbox/a.md")
        #expect(watcher.event(path: "/nonexistent/Library", flags: file)?.path == "")
        #expect(watcher.event(path: "/nonexistent/LibraryOther/a.md", flags: file) == nil)
        #expect(watcher.event(path: "/elsewhere/a.md", flags: file) == nil)
    }

    @Test(arguments: [
        kFSEventStreamEventFlagMustScanSubDirs, kFSEventStreamEventFlagUserDropped,
        kFSEventStreamEventFlagKernelDropped, kFSEventStreamEventFlagRootChanged,
    ])
    func lostEventsNeedRescan(flag: Int) {
        #expect(watcher.event(path: "/nonexistent/Library/Inbox", flags: flags(flag))?.needsRescan == true)
        // Even reported for a path outside the root (the root itself moved), it still counts.
        #expect(watcher.event(path: "/elsewhere", flags: flags(flag))?.needsRescan == true)
    }

    @Test func ordinaryChangesDontNeedRescan() {
        let file = flags(kFSEventStreamEventFlagItemIsFile, kFSEventStreamEventFlagItemRenamed)
        #expect(watcher.event(path: "/nonexistent/Library/Inbox/a.md", flags: file)?.needsRescan == false)
    }

    @Test func removedOrRenamedFoldersAreMarked() {
        let renamedFolder = flags(kFSEventStreamEventFlagItemIsDir, kFSEventStreamEventFlagItemRenamed)
        let removedFolder = flags(kFSEventStreamEventFlagItemIsDir, kFSEventStreamEventFlagItemRemoved)
        let createdFolder = flags(kFSEventStreamEventFlagItemIsDir, kFSEventStreamEventFlagItemCreated)
        let renamedFile = flags(kFSEventStreamEventFlagItemIsFile, kFSEventStreamEventFlagItemRenamed)
        let path = "/nonexistent/Library/Projects"
        #expect(watcher.event(path: path, flags: renamedFolder)?.isFolderRemovedOrRenamed == true)
        #expect(watcher.event(path: path, flags: removedFolder)?.isFolderRemovedOrRenamed == true)
        #expect(watcher.event(path: path, flags: createdFolder)?.isFolderRemovedOrRenamed == false)
        #expect(watcher.event(path: path, flags: renamedFile)?.isFolderRemovedOrRenamed == false)
    }
}
