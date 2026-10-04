import Foundation
import ScrapModel
import ScrapStorage
import ScrapTestSupport
import Testing

struct ScrapImmutabilityTests {
    /// A body that a careless rewrite would change: leading and trailing whitespace, trailing
    /// blank lines, CRLF, a `---` line, and both forms of é.
    static let body = "  2BR, 850 sq ft  \r\n---\n\u{E9}e\u{301} 🏠\t$2,400/mo\n\n \t"

    // MARK: - The third acceptance criterion

    /// Every kind of edit the store offers leaves the body byte-identical. The sample for each
    /// kind comes from an exhaustive switch, so adding an edit to `ScrapEdit` stops this test
    /// building until it has a sample here.
    @Test(arguments: ScrapEdit.Kind.allCases)
    func everyEditLeavesBodyByteIdentical(kind: ScrapEdit.Kind) async throws {
        let (library, store, scrap) = try await Self.storeWithScrap()
        let path = try await store.path(of: scrap.id)
        let before = try Self.bodyBytes(at: library.root.appending(path: path))

        let updated = try await store.update(scrap.id, [Self.sample(for: kind).edit])

        #expect(try Self.bodyBytes(at: library.root.appending(path: path)) == before)
        #expect(Array(updated.body.utf8) == before)
    }

    @Test func noteEditLeavesBodyAndFingerprintByteIdentical() async throws {
        let (library, store, scrap) = try await Self.storeWithScrap()
        let path = try await store.path(of: scrap.id)
        let before = try Self.bodyBytes(at: library.root.appending(path: path))

        try await store.update(scrap.id, [.note("Ask about parking.")])

        let reread = try await store.scrap(atPath: path)
        #expect(try Self.bodyBytes(at: library.root.appending(path: path)) == before)
        #expect(reread.reference.fingerprint == scrap.reference.fingerprint)
        #expect(reread.note?.text == "Ask about parking.")
    }

    /// The body on disk wins: an edit made in another editor survives the app's next update.
    @Test func updateKeepsExternallyEditedBody() async throws {
        let (library, store, scrap) = try await Self.storeWithScrap()
        let url = library.root.appending(path: try await store.path(of: scrap.id))
        var text = try String(contentsOf: url, encoding: .utf8)
        text += "\nadded in another editor"
        try Data(text.utf8).write(to: url)
        let edited = try Self.bodyBytes(at: url)

        try await store.update(scrap.id, [.pinned(true)])

        #expect(try Self.bodyBytes(at: url) == edited)
        #expect(try await store.scrap(atPath: store.path(of: scrap.id)).pinned)
    }

    /// The read-modify-write half of the second acceptance criterion.
    @Test func unknownKeysSurviveNoteEdit() async throws {
        let library = try TemporaryLibrary()
        let store = ScrapStore(root: library.root, clock: FakeWallClock())
        try await store.open()
        try Fixtures.data("obsidian-edited.md").write(to: library.root.appending(path: "Inbox/obsidian.md"))
        let original = try await store.scrap(atPath: "Inbox/obsidian.md")

        try await store.update(original.id, [.note("Ask about parking.")])

        let reread = try await store.scrap(atPath: "Inbox/obsidian.md")
        #expect(reread.extraFrontmatter == original.extraFrontmatter)
        #expect(reread.extraFrontmatter.map(\.key).contains("tags"))
        #expect(reread.body == original.body)
    }

    // MARK: - Creating

    @Test func createWritesFileNamedByTimeAndID() async throws {
        let (library, store, scrap) = try await Self.storeWithScrap()
        let expected = "Inbox/" + LibraryLayout.fileName(created: scrap.created, id: scrap.id)
        #expect(try await store.path(of: scrap.id) == expected)
        let decoded = try FrontmatterCodec.decode(Data(contentsOf: library.root.appending(path: expected)))
        #expect(decoded == scrap)
        #expect(scrap.body == Self.body)
    }

    /// Two scraps that would get the same name: the second gets a suffix, and the first file
    /// is never replaced.
    @Test func createNeverReplacesAnExistingFile() async throws {
        let library = try TemporaryLibrary()
        let store = ScrapStore(root: library.root, clock: FakeWallClock())
        try await store.open()
        let id = try #require(ScrapID(string: "8f3a0c2d-5d0f-4c8e-9a51-3c1e7a2b71e4"))
        let other = try #require(ScrapID(string: "8f3a9999-5d0f-4c8e-9a51-3c1e7a2b71e4"))

        let first = try await store.create(Self.draft(id: id, body: "first"), in: .inbox)
        let second = try await store.create(Self.draft(id: other, body: "second"), in: .inbox)

        let firstPath = try await store.path(of: first.id)
        let secondPath = try await store.path(of: second.id)
        #expect(firstPath != secondPath)
        #expect(secondPath.hasSuffix("-8f3a-2.md"))
        #expect(try await store.scrap(atPath: firstPath).body == "first")
        #expect(try await store.scrap(atPath: secondPath).body == "second")
    }

    /// Title and note edits count for `updated` (time sorting); pinning, board order, and the
    /// system's reference and asset updates don't (confirmed 2026-10-04).
    @Test(arguments: ScrapEdit.Kind.allCases)
    func onlyContentEditsBumpUpdated(kind: ScrapEdit.Kind) async throws {
        let clock = FakeWallClock()
        let (library, store, scrap) = try await Self.storeWithScrap(clock: clock)
        defer { withExtendedLifetime(library) {} }
        clock.advance(by: 60)

        let sample = Self.sample(for: kind)
        let updated = try await store.update(scrap.id, [sample.edit])
        #expect(updated.updated == (sample.bumpsUpdated ? clock.now() : scrap.updated))
        #expect(try await store.scrap(atPath: store.path(of: scrap.id)).updated == updated.updated)
    }

    @Test func noteEditSetsNoteDateAndNilRemovesIt() async throws {
        let clock = FakeWallClock()
        let (library, store, scrap) = try await Self.storeWithScrap(clock: clock)
        defer { withExtendedLifetime(library) {} }
        clock.advance(by: 60)

        let noted = try await store.update(scrap.id, [.note("n")])
        #expect(noted.note?.updated == clock.now())

        let cleared = try await store.update(scrap.id, [.note(nil)])
        #expect(cleared.note == nil)
    }

    /// No edits, no write: a file formatted by another editor stays exactly as it is.
    @Test func emptyEditsLeaveFileUntouched() async throws {
        let library = try TemporaryLibrary()
        let store = ScrapStore(root: library.root, clock: FakeWallClock())
        try await store.open()
        let url = library.root.appending(path: "Inbox/obsidian.md")
        try Fixtures.data("obsidian-edited.md").write(to: url)
        let scrap = try await store.scrap(atPath: "Inbox/obsidian.md")

        try await store.update(scrap.id, [])
        #expect(try Data(contentsOf: url) == Fixtures.data("obsidian-edited.md"))
    }

    @Test func updateOfUnknownScrapThrows() async throws {
        let (library, store, _) = try await Self.storeWithScrap()
        defer { withExtendedLifetime(library) {} }
        let unknown = ScrapID()
        await #expect(throws: StoreError.unknownScrap(unknown)) { try await store.update(unknown, [.pinned(true)]) }
    }

    /// The id is authoritative, so a second file with a known id is refused.
    @Test func createRefusesAKnownID() async throws {
        let (library, store, scrap) = try await Self.storeWithScrap()
        defer { withExtendedLifetime(library) {} }
        await #expect(throws: StoreError.idInUse(scrap.id)) {
            try await store.create(Self.draft(id: scrap.id), in: .inbox)
        }
    }

    // MARK: - Helpers

    /// One edit of each kind, and whether it should bump `updated`.
    static func sample(for kind: ScrapEdit.Kind) -> (edit: ScrapEdit, bumpsUpdated: Bool) {
        switch kind {
        case .title: (.title("New title"), true)
        case .note: (.note("A note"), true)
        case .pinned: (.pinned(true), false)
        case .board: (.board(Rank.after(Rank.after(nil))), false)
        case .reference:
            (
                .reference(
                    Reference(
                        provider: .safari, app: AppIdentity(bundleID: "com.apple.Safari"),
                        locator: .url(URL(filePath: "/")), label: "example.com",
                        fingerprint: Fingerprint.text(body))), false
            )
        case .asset: (.asset(AssetRef(path: "assets/8f3a-thumb.png")), false)
        }
    }

    static func draft(id: ScrapID = ScrapID(), body: String = body) -> ScrapDraft {
        ScrapDraft(
            id: id,
            kind: .text,
            title: "2BR on Elm St",
            body: body,
            reference: Reference(
                provider: .fallback, app: AppIdentity(bundleID: "com.apple.TextEdit"), locator: .app,
                label: "TextEdit", fingerprint: Fingerprint.text(body)),
            board: Rank.after(nil),
            created: Date(timeIntervalSince1970: 1_790_690_531)
        )
    }

    static func storeWithScrap(clock: FakeWallClock = FakeWallClock()) async throws
        -> (TemporaryLibrary, ScrapStore, Scrap)
    {
        let library = try TemporaryLibrary()
        let store = ScrapStore(root: library.root, clock: clock)
        try await store.open()
        let scrap = try await store.create(draft(), in: .inbox)
        return (library, store, scrap)
    }

    /// The bytes after the closing `---` line, read straight from the file.
    static func bodyBytes(at url: URL) throws -> [UInt8] {
        let bytes = Array(try Data(contentsOf: url))
        let marker = Array("\n---\n".utf8)
        try #require(bytes.count >= 4 + marker.count, "file too short to hold frontmatter")
        let start = try #require(
            (4..<(bytes.count - marker.count + 1)).first { Array(bytes[$0..<($0 + marker.count)]) == marker })
        return Array(bytes[(start + marker.count)...])
    }
}
