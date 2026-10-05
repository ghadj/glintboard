import Foundation
import ScrapModel
import ScrapTestSupport
import Testing

@testable import ScrapStorage

struct ScrapIndexTests {
    @Test func detectsFTS5InSystemSQLite() async throws {
        let (library, index) = try await IndexFixtures.openIndex()
        defer { withExtendedLifetime(library) {} }
        #expect(await index.engine == .fts5)
    }

    @Test func usesWALJournalMode() async throws {
        let (library, index) = try await IndexFixtures.openIndex()
        await index.close()
        let connection = try SQLiteConnection(
            path: library.base.appending(path: ".index.sqlite").path(percentEncoded: false))
        #expect(try connection.scalarText("PRAGMA journal_mode") == "wal")
    }

    @Test func appliesSavedUpdatedAndRemovedChanges() async throws {
        let (library, index) = try await IndexFixtures.openIndex()
        defer { withExtendedLifetime(library) {} }
        var scrap = IndexFixtures.scrap(title: "First", body: "body")
        try await index.apply(IndexFixtures.saved(scrap, at: "Inbox/a.md"))
        #expect(try await index.cards(in: .inbox).map(\.title) == ["First"])

        // Edited outside the app and moved to another name: one card, at the new path.
        scrap.title = "Second"
        try await index.apply(.updated(scrap, file: ScrapFileInfo(path: "Inbox/b.md", modified: .now, size: 4)))
        let cards = try await index.cards(in: .inbox)
        #expect(cards.map(\.title) == ["Second"])
        #expect(cards.map(\.path) == ["Inbox/b.md"])
        #expect(try await index.search(SearchQuery("second")) == [scrap.id])
        #expect(try await index.search(SearchQuery("first")).isEmpty)

        try await index.apply(.removed(path: "Inbox/b.md", id: scrap.id))
        #expect(try await index.cards(in: .inbox).isEmpty)
        #expect(try await index.search(SearchQuery("second")).isEmpty)
    }

    /// A file that becomes unreadable no longer shows its old content.
    @Test func problemRemovesTheStaleRow() async throws {
        let (library, index) = try await IndexFixtures.openIndex()
        defer { withExtendedLifetime(library) {} }
        try await index.apply(IndexFixtures.saved(IndexFixtures.scrap(body: "old"), at: "Inbox/a.md"))
        try await index.apply(.problem(path: "Inbox/a.md", .missingKey("id")))
        #expect(try await index.cards(in: .inbox).isEmpty)
    }

    /// Another scrap now in a path that had a row: the stale row goes.
    @Test func newScrapAtAnExistingPathReplacesTheRow() async throws {
        let (library, index) = try await IndexFixtures.openIndex()
        defer { withExtendedLifetime(library) {} }
        let first = IndexFixtures.scrap(title: "First")
        let second = IndexFixtures.scrap(title: "Second")
        try await index.apply(IndexFixtures.saved(first, at: "Inbox/a.md"))
        try await index.apply(IndexFixtures.saved(second, at: "Inbox/a.md"))
        #expect(try await index.cards(in: .inbox).map(\.id) == [second.id])
    }

    @Test func cardsCarryWhatACardShows() async throws {
        let (library, index) = try await IndexFixtures.openIndex()
        defer { withExtendedLifetime(library) {} }
        var scrap = IndexFixtures.scrap(title: "Elm St", body: String(repeating: "x", count: 500), note: "n")
        scrap.pinned = true
        scrap.asset = AssetRef(path: "assets/8f3a-thumb.png")
        try await index.apply(IndexFixtures.saved(scrap, at: "Inbox/a.md"))

        let card = try #require(try await index.cards(in: .inbox).first)
        #expect(card.id == scrap.id)
        #expect(card.title == "Elm St")
        #expect(card.preview.count == 300)
        #expect(card.pinned)
        #expect(card.hasNote)
        #expect(card.asset == "assets/8f3a-thumb.png")
        #expect(card.label == "TextEdit")
        #expect(card.provider == .fallback)
        #expect(card.updated == scrap.updated)
    }

    @Test func cardsAreNewestFirst() async throws {
        let (library, index) = try await IndexFixtures.openIndex()
        defer { withExtendedLifetime(library) {} }
        let older = IndexFixtures.scrap(title: "Older", updated: IndexFixtures.created)
        let newer = IndexFixtures.scrap(title: "Newer", updated: IndexFixtures.created.addingTimeInterval(60))
        try await index.apply(IndexFixtures.saved(older))
        try await index.apply(IndexFixtures.saved(newer))
        #expect(try await index.cards(in: .inbox).map(\.title) == ["Newer", "Older"])
    }

    @Test func fileStatesAndLastRank() async throws {
        let (library, index) = try await IndexFixtures.openIndex()
        defer { withExtendedLifetime(library) {} }
        let low = IndexFixtures.scrap(board: Rank.after(nil))
        let high = IndexFixtures.scrap(board: Rank.after(Rank.after(nil)))
        try await index.apply(IndexFixtures.saved(high, at: "Inbox/b.md"))
        try await index.apply(IndexFixtures.saved(low, at: "Inbox/a.md"))

        #expect(try await index.lastRank(in: .inbox) == high.board)
        let states = try await index.fileStates()
        #expect(states["Inbox/a.md"] == ScrapFileInfo(path: "Inbox/a.md", modified: IndexFixtures.created, size: 0))
        #expect(states.count == 2)
    }

    /// Health lives only in the index: setting it never touches the scrap's file, and it
    /// survives later edits of the same scrap.
    @Test func healthIsStoredOnlyInIndex() async throws {
        let library = try TemporaryLibrary()
        let store = ScrapStore(root: library.root, clock: FakeWallClock())
        try await store.open()
        let index = ScrapIndex(databaseURL: library.root.appending(path: ".index.sqlite"))
        try await index.open()
        let changes = StreamRecorder(await store.changes())
        let scrap = try await store.create(ScrapImmutabilityTests.draft(), in: .inbox)
        let change = await changes.waitFor { $0.path != nil }
        let saved = try #require(change)
        try await index.apply(saved)

        let url = library.root.appending(path: try await store.path(of: scrap.id))
        let bytes = try Data(contentsOf: url)
        let modified = try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate

        let health = ReferenceHealth(status: .trashed, lastChecked: IndexFixtures.created)
        try await index.setHealth(health, for: scrap.id)
        #expect(try await index.health(of: scrap.id) == health)
        #expect(try Data(contentsOf: url) == bytes)
        #expect(try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate == modified)

        try await index.apply(saved)
        #expect(try await index.health(of: scrap.id) == health)
    }

    /// Reconciliation compares these exactly, and file system dates have sub-second precision.
    @Test func modificationDatesComeBackExactly() async throws {
        let (library, index) = try await IndexFixtures.openIndex()
        defer { withExtendedLifetime(library) {} }
        let modified = Date(timeIntervalSinceReferenceDate: 812_345_678.123456789)
        let file = ScrapFileInfo(path: "Inbox/a.md", modified: modified, size: 10)
        try await index.apply(.updated(IndexFixtures.scrap(), file: file))
        #expect(try await index.fileStates()["Inbox/a.md"] == file)
    }

    /// Health goes with its scrap's row: foreign keys are on for the connection.
    @Test func removingAScrapRemovesItsHealth() async throws {
        let (library, index) = try await IndexFixtures.openIndex()
        defer { withExtendedLifetime(library) {} }
        let scrap = IndexFixtures.scrap()
        try await index.apply(IndexFixtures.saved(scrap, at: "Inbox/a.md"))
        try await index.setHealth(ReferenceHealth(status: .missing, lastChecked: IndexFixtures.created), for: scrap.id)

        try await index.apply(.removed(path: "Inbox/a.md", id: scrap.id))
        try await index.apply(IndexFixtures.saved(scrap, at: "Inbox/a.md"))
        #expect(try await index.health(of: scrap.id) == nil)
    }

    @Test func textWithNULCharactersIsKeptWhole() async throws {
        let (library, index) = try await IndexFixtures.openIndex()
        defer { withExtendedLifetime(library) {} }
        try await index.apply(IndexFixtures.saved(IndexFixtures.scrap(title: "before\u{0}after")))
        #expect(try await index.cards(in: .inbox).first?.title == "before\u{0}after")
    }

    @Test func healthOfUnknownScrapIsNil() async throws {
        let (library, index) = try await IndexFixtures.openIndex()
        defer { withExtendedLifetime(library) {} }
        #expect(try await index.health(of: ScrapID()) == nil)
    }
}
