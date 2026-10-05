import Foundation
import ScrapModel
import ScrapStorage
import ScrapTestSupport
import Testing

/// Real FSEvents on a temporary library. Every wait has a deadline that fails the test; no
/// test sleeps for a fixed time. Each test stops its watcher even when it fails, so no FSEvents
/// stream outlives its test.
@Suite(.timeLimit(.minutes(1)))
struct StoreEchoTests {
    // MARK: - The eighth acceptance criterion

    /// The store's own writes come back from FSEvents, but must not look like edits. A sentinel
    /// file written afterwards proves the echoes have been processed: FSEvents reports events in
    /// order, so once the sentinel's change arrives, any reload of the store's file would have too.
    @Test func ownWriteProducesNoChange() async throws {
        try await Self.withWatchedStore { library, store, changes in
            let scrap = try await store.create(ScrapImmutabilityTests.draft(), in: .inbox)
            try await store.update(scrap.id, [.pinned(true)])
            let path = try await store.path(of: scrap.id)

            try Fixtures.data("design-example.md").write(to: library.root.appending(path: "Inbox/sentinel.md"))
            let sentinel = await changes.waitFor(within: 10) { $0.path == "Inbox/sentinel.md" }
            #expect(sentinel?.path == "Inbox/sentinel.md")

            let reloads = changes.values.filter {
                if case .updated(_, let file) = $0 { file.path == path } else { false }
            }
            #expect(reloads.isEmpty, "the store's own writes were reported as edits: \(reloads)")
            let saves = changes.values.filter { if case .saved(_, let file) = $0 { file.path == path } else { false } }
            #expect(saves.count == 2)
        }
    }

    @Test func externalEditToSameFileProducesChange() async throws {
        try await Self.withWatchedStore { library, store, changes in
            let scrap = try await store.create(ScrapImmutabilityTests.draft(), in: .inbox)
            let path = try await store.path(of: scrap.id)

            let url = library.root.appending(path: path)
            let edited = try String(contentsOf: url, encoding: .utf8) + "\nedited elsewhere"
            try Data(edited.utf8).write(to: url)

            // The store's own save has the same path, so wait for a sentinel written after the
            // edit, then look for the edit among everything recorded.
            try Fixtures.data("design-example.md").write(to: library.root.appending(path: "Inbox/sentinel.md"))
            let sentinel = await changes.waitFor(within: 10) { $0.path == "Inbox/sentinel.md" }
            #expect(sentinel?.path == "Inbox/sentinel.md")
            let edits = changes.values.filter { $0.isUpdate(at: path, bodyEndingWith: "edited elsewhere") }
            #expect(edits.count == 1, "changes: \(changes.values.map(IndexFollowerTests.describe))")
        }
    }

    // MARK: - Other changes

    @Test func externalCreateAndDeleteAreReported() async throws {
        try await Self.withWatchedStore { library, _, changes in
            let url = library.root.appending(path: "Inbox/copied-in.md")
            let id = try #require(ScrapID(string: "8f3a0c2d-5d0f-4c8e-9a51-3c1e7a2b71e4"))

            try Fixtures.data("design-example.md").write(to: url)
            let created = await changes.waitFor(within: 10) { $0.path == "Inbox/copied-in.md" }
            #expect(created?.isUpdate(at: "Inbox/copied-in.md", of: id) == true)

            try FileManager.default.removeItem(at: url)
            let removed = await changes.waitFor(within: 10) { $0 == .removed(path: "Inbox/copied-in.md", id: id) }
            #expect(removed != nil)
        }
    }

    @Test func ignoresTrashIndexAndTemporaryFiles() async throws {
        try await Self.withWatchedStore { library, _, changes in
            let files = FileManager.default
            let example = try Fixtures.data("design-example.md")
            for folder in [".trash/20261004-120000/Inbox", "Inbox/assets"] {
                try files.createDirectory(at: library.root.appending(path: folder), withIntermediateDirectories: true)
            }
            try example.write(to: library.root.appending(path: ".trash/20261004-120000/Inbox/old.md"))
            try example.write(to: library.root.appending(path: "Inbox/assets/thumb.md"))
            try example.write(to: library.root.appending(path: ".index.sqlite"))
            try example.write(to: library.root.appending(path: ".index.sqlite-wal"))
            try example.write(to: library.root.appending(path: "Inbox/.hidden.md"))
            try example.write(to: library.root.appending(path: "Inbox/notes.txt"))
            try example.write(to: library.root.appending(path: "at-the-root.md"))
            try Data("{}".utf8).write(to: library.root.appending(path: "Inbox/.collection.json"))

            try example.write(to: library.root.appending(path: "Inbox/sentinel.md"))
            let sentinel = await changes.waitFor(within: 10) { $0.path == "Inbox/sentinel.md" }
            #expect(sentinel?.path == "Inbox/sentinel.md")
            let others = changes.values.filter { $0.path != "Inbox/sentinel.md" }
            #expect(others.isEmpty, "unexpected changes: \(others)")
        }
    }

    @Test func unparseableExternalEditBecomesProblem() async throws {
        try await Self.withWatchedStore { library, _, changes in
            try Fixtures.data("unsupported/anchor.md").write(to: library.root.appending(path: "Inbox/broken.md"))

            let problem = await changes.waitFor(within: 10) {
                $0 == .problem(path: "Inbox/broken.md", .unsupportedSyntax(line: 5, construct: .anchor))
            }
            #expect(problem != nil)
            // The file is left exactly as it was.
            #expect(
                try Data(contentsOf: library.root.appending(path: "Inbox/broken.md"))
                    == Fixtures.data("unsupported/anchor.md"))
        }
    }

    /// Moving a whole collection folder (to the Trash, say) is reported as the folder alone, so
    /// the store asks for a rescan instead of missing every scrap inside it.
    @Test func renamedCollectionFolderNeedsRescan() async throws {
        try await Self.withWatchedStore { library, _, changes in
            let files = FileManager.default
            let folder = library.root.appending(path: "Projects")
            try files.createDirectory(at: folder, withIntermediateDirectories: false)
            try Fixtures.data("design-example.md").write(to: folder.appending(path: "a.md"))
            let created = await changes.waitFor(within: 10) { $0.path == "Projects/a.md" }
            #expect(created?.path == "Projects/a.md")

            try files.moveItem(at: folder, to: library.base.appending(path: "Projects"))
            let rescan = await changes.waitFor(within: 10) { $0 == .rescanNeeded }
            #expect(rescan == .rescanNeeded)
        }
    }

    /// A Finder copy of a scrap carries the same id. Until reconciliation gives it a fresh one,
    /// the id stays with the original file, so the app's edits never land in the copy.
    @Test func copyOfKnownScrapKeepsTheOriginalPath() async throws {
        try await Self.withWatchedStore { library, store, changes in
            let scrap = try await store.create(ScrapImmutabilityTests.draft(), in: .inbox)
            let original = try await store.path(of: scrap.id)
            try FileManager.default.copyItem(
                at: library.root.appending(path: original), to: library.root.appending(path: "Inbox/copy.md"))

            try Fixtures.data("design-example.md").write(to: library.root.appending(path: "Inbox/sentinel.md"))
            let sentinel = await changes.waitFor(within: 10) { $0.path == "Inbox/sentinel.md" }
            #expect(sentinel?.path == "Inbox/sentinel.md")
            let copies = changes.values.filter { $0.path == "Inbox/copy.md" }
            #expect(copies.isEmpty)
            #expect(try await store.path(of: scrap.id) == original)
        }
    }

    // MARK: - Helpers

    /// A store watching a fresh library, stopped afterwards whether `body` succeeds or throws.
    static func withWatchedStore(
        _ body: (TemporaryLibrary, ScrapStore, StreamRecorder<LibraryChange>) async throws -> Void
    ) async throws {
        let library = try TemporaryLibrary()
        let store = ScrapStore(root: library.root, clock: FakeWallClock())
        try await store.open()
        let changes = StreamRecorder(await store.changes())
        try await store.startWatching()
        do {
            try await body(library, store, changes)
        } catch {
            await store.stopWatching()
            throw error
        }
        await store.stopWatching()
    }
}
