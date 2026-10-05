import Foundation
import ScrapModel
import ScrapStorage
import ScrapTestSupport
import Testing

/// A library being watched, with its index and the follower that keeps them in step.
struct FollowedLibrary {
    let library: TemporaryLibrary
    let store: ScrapStore
    let index: ScrapIndex
    let follower: IndexFollower
    let changes: StreamRecorder<LibraryChange>

    /// Stopped afterwards whether `body` succeeds or throws.
    static func with(_ body: (FollowedLibrary) async throws -> Void) async throws {
        let library = try TemporaryLibrary()
        let store = ScrapStore(root: library.root, clock: FakeWallClock())
        try await store.open()
        let index = ScrapIndex(databaseURL: library.root.appending(path: ".index.sqlite"))
        try await index.open()
        let follower = IndexFollower(store: store, index: index)
        let changes = StreamRecorder(await follower.changes())
        await follower.start()
        try await store.startWatching()
        let followed = FollowedLibrary(
            library: library, store: store, index: index, follower: follower, changes: changes)
        do {
            try await body(followed)
        } catch {
            await followed.stop()
            throw error
        }
        await followed.stop()
    }

    func stop() async {
        await store.stopWatching()
        await follower.stop()
    }
}

@Suite(.timeLimit(.minutes(1)))
struct IndexFollowerTests {
    /// A change the follower passes on is already in the index, so the shelf never shows a card
    /// that search can't find.
    @Test func changesArriveAfterTheIndexHasThem() async throws {
        try await FollowedLibrary.with { followed in
            let scrap = try await followed.store.create(ScrapImmutabilityTests.draft(), in: .inbox)
            let path = try await followed.store.path(of: scrap.id)
            let saved = await followed.changes.waitFor(within: 10) { $0.path == path }
            #expect(saved?.kind == "saved")
            #expect(try await followed.index.cards(in: .inbox).map(\.id) == [scrap.id])
        }
    }

    @Test func externalDeleteRemovesTheRow() async throws {
        try await FollowedLibrary.with { followed in
            let url = followed.library.root.appending(path: "Inbox/outside.md")
            try Fixtures.data("design-example.md").write(to: url)
            let created = await followed.changes.waitFor(within: 10) { $0.path == "Inbox/outside.md" }
            #expect(created?.kind == "updated")
            #expect(try await followed.index.cards(in: .inbox).count == 1)

            let id = try #require(ScrapID(string: "8f3a0c2d-5d0f-4c8e-9a51-3c1e7a2b71e4"))
            try FileManager.default.removeItem(at: url)
            let removed = await followed.changes.waitFor(within: 10) {
                $0 == .removed(path: "Inbox/outside.md", id: id)
            }
            #expect(removed == .removed(path: "Inbox/outside.md", id: id))
            let cards = try await followed.index.cards(in: .inbox)
            #expect(
                cards.isEmpty,
                "cards left: \(cards.map(\.path)); changes: \(followed.changes.values.map(Self.describe))")
        }
    }

    /// A short form of a change for failure messages.
    static func describe(_ change: LibraryChange) -> String {
        switch change {
        case .saved(_, let file): "saved \(file.path)"
        case .updated(_, let file): "updated \(file.path)"
        case .removed(let path, let id): "removed \(path) \(id?.shortHex ?? "nil")"
        case .problem(let path, let error): "problem \(path) \(error)"
        case .rescanNeeded: "rescan"
        }
    }
}

/// The store half of the fourth acceptance criterion: a file outside the YAML subset is
/// logged and skipped, never indexed, and left exactly as it was.
@Suite(.timeLimit(.minutes(1)))
struct ProblemFileTests {
    @Test(arguments: [
        ("anchor", UnsupportedConstruct.anchor, 5), ("alias", .alias, 5), ("tag", .tag, 5),
        ("flow-map", .flowMap, 15), ("folded-scalar", .foldedScalar, 15), ("nested-map", .nestedMap, 15),
        ("comment", .comment, 15), ("document-marker", .documentMarker, 10),
    ])
    func unparseableFileIsLoggedSkippedAndUntouched(
        fixture: String, construct: UnsupportedConstruct, line: Int
    ) async throws {
        try await FollowedLibrary.with { followed in
            let original = try Fixtures.data("unsupported/\(fixture).md")
            let url = followed.library.root.appending(path: "Inbox/\(fixture).md")
            try original.write(to: url)
            let modified = try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate

            let expected = LibraryChange.problem(
                path: "Inbox/\(fixture).md", .unsupportedSyntax(line: line, construct: construct))
            let problem = await followed.changes.waitFor(within: 10) { $0 == expected }
            #expect(problem == expected)
            #expect(try await followed.index.cards(in: .inbox).isEmpty)
            #expect(try Data(contentsOf: url) == original)
            #expect(try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate == modified)
        }
    }
}
