import Foundation
import ScrapModel
import ScrapTestSupport
import Testing

@testable import ScrapStorage

/// The index is a cache: one that can't be used is deleted and built again, never repaired.
/// Refilling it from the files is reconciliation's job (M1-R10), which also covers the
/// eleventh acceptance criterion (deleting the index and reopening restores the same results).
struct IndexRebuildTests {
    private func indexURL(_ library: TemporaryLibrary) -> URL {
        library.base.appending(path: ".index.sqlite")
    }

    @Test func missingIndexIsCreated() async throws {
        let library = try TemporaryLibrary()
        defer { withExtendedLifetime(library) {} }
        let index = ScrapIndex(databaseURL: indexURL(library))
        #expect(try await index.open() == .created)
        #expect(FileManager.default.fileExists(atPath: indexURL(library).path(percentEncoded: false)))
    }

    @Test func existingIndexIsReopenedWithItsRows() async throws {
        let library = try TemporaryLibrary()
        defer { withExtendedLifetime(library) {} }
        let first = ScrapIndex(databaseURL: indexURL(library))
        try await first.open()
        let scrap = IndexFixtures.scrap(body: "apartment")
        try await first.apply(IndexFixtures.saved(scrap))
        await first.close()

        let second = ScrapIndex(databaseURL: indexURL(library))
        #expect(try await second.open() == .opened)
        #expect(try await second.search(SearchQuery("apartment")) == [scrap.id])
    }

    @Test func corruptIndexIsRebuilt() async throws {
        let library = try TemporaryLibrary()
        defer { withExtendedLifetime(library) {} }
        try Data(repeating: 0x42, count: 8_192).write(to: indexURL(library))

        let index = ScrapIndex(databaseURL: indexURL(library))
        #expect(try await index.open() == .rebuilt(.corrupt))
        let scrap = IndexFixtures.scrap(body: "apartment")
        try await index.apply(IndexFixtures.saved(scrap))
        #expect(try await index.search(SearchQuery("apartment")) == [scrap.id])
    }

    @Test func otherSchemaVersionIsRebuilt() async throws {
        let library = try TemporaryLibrary()
        defer { withExtendedLifetime(library) {} }
        let first = ScrapIndex(databaseURL: indexURL(library))
        try await first.open()
        try await first.apply(IndexFixtures.saved(IndexFixtures.scrap(body: "apartment")))
        await first.close()
        do {
            // Closed before the index reopens, so it can't delete the new index's log on close.
            let connection = try SQLiteConnection(path: indexURL(library).path(percentEncoded: false))
            try connection.execute("PRAGMA user_version = 99")
        }

        let second = ScrapIndex(databaseURL: indexURL(library))
        #expect(try await second.open() == .rebuilt(.otherVersion(99)))
        #expect(try await second.search(SearchQuery("apartment")).isEmpty)
    }

    /// An index built with one full-text engine is rebuilt for the other.
    @Test func otherEngineIsRebuilt() async throws {
        let library = try TemporaryLibrary()
        defer { withExtendedLifetime(library) {} }
        let first = ScrapIndex(databaseURL: indexURL(library), engine: .fts5)
        try await first.open()
        await first.close()

        let second = ScrapIndex(databaseURL: indexURL(library), engine: .fts4)
        #expect(try await second.open() == .rebuilt(.otherEngine))
        #expect(await second.engine == .fts4)
    }

    @Test func useBeforeOpenThrows() async throws {
        let library = try TemporaryLibrary()
        defer { withExtendedLifetime(library) {} }
        let index = ScrapIndex(databaseURL: indexURL(library))
        await #expect(throws: IndexError.notOpen) { try await index.search(SearchQuery("x")) }
    }
}
