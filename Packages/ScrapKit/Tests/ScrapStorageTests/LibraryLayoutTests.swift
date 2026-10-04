import Foundation
import ScrapModel
import ScrapStorage
import ScrapTestSupport
import Testing

struct LibraryLayoutTests {
    // MARK: - Location

    @Test func defaultRootUsesBundleIdentifier() {
        let support = URL(filePath: "/Users/me/Library/Application Support", directoryHint: .isDirectory)
        let release = LibraryLocation.defaultRoot(bundleIdentifier: "com.example.app", applicationSupport: support)
        let dev = LibraryLocation.defaultRoot(bundleIdentifier: "com.example.app.dev", applicationSupport: support)
        #expect(release.path(percentEncoded: false) == "/Users/me/Library/Application Support/com.example.app/Library/")
        #expect(dev.path(percentEncoded: false) == "/Users/me/Library/Application Support/com.example.app.dev/Library/")
    }

    @Test func defaultRootIsInApplicationSupport() {
        let root = LibraryLocation.defaultRoot(bundleIdentifier: "com.example.app")
        let support = URL.applicationSupportDirectory.path(percentEncoded: false)
        let expected = (support.hasSuffix("/") ? support : support + "/") + "com.example.app/Library/"
        #expect(root.path(percentEncoded: false) == expected)
    }

    // MARK: - File names

    @Test func fileNameUsesCreatedTimeAndShortHex() throws {
        let id = try #require(ScrapID(string: "8f3a0c2d-5d0f-4c8e-9a51-3c1e7a2b71e4"))
        let created = Date(timeIntervalSince1970: 1_790_759_742)  // 2026-09-30T09:15:42Z
        let utc = try #require(TimeZone(identifier: "UTC"))
        let nicosia = try #require(TimeZone(identifier: "Asia/Nicosia"))  // UTC+3 in September
        #expect(LibraryLayout.fileName(created: created, id: id, timeZone: utc) == "2026-09-30-0915-8f3a.md")
        #expect(LibraryLayout.fileName(created: created, id: id, timeZone: nicosia) == "2026-09-30-1215-8f3a.md")
    }

    @Test func collidingNamesGetNumericSuffix() {
        #expect(LibraryLayout.uniqueName("a.md", existing: []) == "a.md")
        #expect(LibraryLayout.uniqueName("a.md", existing: ["a.md"]) == "a-2.md")
        #expect(LibraryLayout.uniqueName("a.md", existing: ["a.md", "a-2.md"]) == "a-3.md")
        // The default macOS file system ignores case.
        #expect(LibraryLayout.uniqueName("a.md", existing: ["A.MD"]) == "a-2.md")
        #expect(LibraryLayout.uniqueName("plan.png", existing: ["plan.png"]) == "plan-2.png")
        #expect(LibraryLayout.uniqueName("README", existing: ["README"]) == "README-2")
        // It also ignores Unicode composition: é as one code point or as e plus an accent.
        #expect(LibraryLayout.uniqueName("cafe\u{301}.md", existing: ["caf\u{E9}.md"]) == "cafe\u{301}-2.md")
    }

    // MARK: - Collection names

    @Test(arguments: ["Inbox", "Apartment hunt", "Ελληνικά 🏠", "a.b"])
    func acceptsCollectionNames(name: String) {
        #expect(CollectionName(name)?.rawValue == name)
    }

    @Test(arguments: ["", ".hidden", "a/b", "a:b", " ", "Inbox\n"])
    func rejectsCollectionNames(name: String) {
        #expect(CollectionName(name) == nil)
    }

    // MARK: - The store

    @Test func openCreatesInboxWithCollectionJSON() async throws {
        let library = try TemporaryLibrary()
        let clock = FakeWallClock()
        let store = ScrapStore(root: library.root, clock: clock)
        try await store.open()

        let inbox = library.root.appending(path: "Inbox", directoryHint: .isDirectory)
        var isDirectory: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: inbox.path(percentEncoded: false), isDirectory: &isDirectory))
        #expect(isDirectory.boolValue)

        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: inbox.appending(path: ".collection.json")))
        let object = try #require(json as? [String: Any])
        #expect(object["order"] as? Int == 0)
        #expect(object["created"] as? String == "2026-09-29T14:02:11Z")
        #expect(object["schema"] as? Int == 1)

        let collections = try await store.collections()
        #expect(collections == [CollectionInfo(name: "Inbox", order: 0, created: clock.now())])
    }

    @Test func openKeepsExistingCollectionJSON() async throws {
        let library = try TemporaryLibrary()
        let clock = FakeWallClock()
        try await ScrapStore(root: library.root, clock: clock).open()
        let file = library.root.appending(path: "Inbox/.collection.json")
        let before = try Data(contentsOf: file)

        clock.advance(by: 3_600)
        try await ScrapStore(root: library.root, clock: clock).open()
        #expect(try Data(contentsOf: file) == before)
    }

    @Test func collectionJSONKeepsUnknownKeys() throws {
        let original = Data(
            #"{"aiExcluded":true,"color":"blue","created":"2026-09-29T14:02:11Z","nested":{"list":[1,2.5,null,"x"]},"order":2,"schema":1}"#
                .utf8)
        let info = try CollectionFile.decode(original, name: "Apartment hunt")
        #expect(info.name == "Apartment hunt")
        #expect(info.order == 2)
        #expect(info.created == Date(timeIntervalSince1970: 1_790_690_531))
        let expectedExtra: [String: JSONValue] = [
            "aiExcluded": .bool(true),
            "color": .string("blue"),
            "nested": .object(["list": .array([.integer(1), .number(2.5), .null, .string("x")])]),
        ]
        #expect(info.extra == expectedExtra)

        // Written back and read again, every unknown key keeps its value and its JSON type.
        let rewritten = try CollectionFile.encode(info)
        #expect(String(decoding: rewritten, as: UTF8.self).contains("\"schema\" : 1"))
        #expect(try CollectionFile.decode(rewritten, name: "Apartment hunt") == info)
    }

    @Test func collectionJSONWithoutSchemaReadsAsSchemaOne() throws {
        let data = Data(#"{"created":"2026-09-29T14:02:11Z","order":3}"#.utf8)
        #expect(try CollectionFile.decode(data, name: "Inbox").order == 3)
    }

    @Test(arguments: [
        #"not json"#,
        #"{"created":"2026-09-29T14:02:11Z"}"#,
        #"{"order":1}"#,
        #"{"order":"1","created":"2026-09-29T14:02:11Z"}"#,
        #"{"order":1,"created":"yesterday"}"#,
        #"{"order":1,"created":"2026-09-29T14:02:11Z","schema":"1"}"#,
        #"{"order":1,"created":"2026-09-29T14:02:11Z","schema":0}"#,
    ])
    func invalidCollectionJSONIsRejected(json: String) {
        #expect(throws: StoreError.invalidCollectionFile(path: "Inbox/.collection.json")) {
            try CollectionFile.decode(Data(json.utf8), name: "Inbox")
        }
    }

    @Test func newerCollectionSchemaIsRejected() {
        let data = Data(#"{"created":"2026-09-29T14:02:11Z","order":1,"schema":2}"#.utf8)
        #expect(throws: StoreError.newerCollectionSchema(path: "Inbox/.collection.json", 2)) {
            try CollectionFile.decode(data, name: "Inbox")
        }
    }

    /// A folder made in Finder, or one whose `.collection.json` can't be read, is still a
    /// collection: listed after the others, by name, and left unchanged.
    @Test func collectionsWithoutReadableFileAreListedLast() async throws {
        let library = try TemporaryLibrary()
        let store = ScrapStore(root: library.root, clock: FakeWallClock())
        try await store.open()
        let files = FileManager.default
        try files.createDirectory(at: library.root.appending(path: "Zeta"), withIntermediateDirectories: false)
        try files.createDirectory(at: library.root.appending(path: "Alpha"), withIntermediateDirectories: false)
        let invalid = library.root.appending(path: "Alpha/.collection.json")
        try Data("not json".utf8).write(to: invalid)
        try files.createDirectory(at: library.root.appending(path: ".trash"), withIntermediateDirectories: false)

        let collections = try await store.collections()
        #expect(collections.map(\.name) == ["Inbox", "Alpha", "Zeta"])
        #expect(collections.dropFirst().allSatisfy { $0.order == .max })
        #expect(try Data(contentsOf: invalid) == Data("not json".utf8))
    }

    /// FSEvents reports resolved paths, so the store's tests need a root without symlinks.
    @Test func temporaryLibraryPathIsFullyResolved() throws {
        let library = try TemporaryLibrary()
        let path = String(library.base.path(percentEncoded: false).dropLast())  // without the trailing "/"
        let resolved = try #require(realpath(path, nil))
        defer { free(resolved) }
        #expect(String(cString: resolved) == path)
    }

    @Test func idComesFromFrontmatterNotFileName() async throws {
        let library = try TemporaryLibrary()
        let store = ScrapStore(root: library.root, clock: FakeWallClock())
        try await store.open()
        // Named as if it belonged to a scrap whose id starts with ffff.
        let misleading = library.root.appending(path: "Inbox/2026-01-01-0000-ffff.md")
        try Fixtures.data("design-example.md").write(to: misleading)

        let scrap = try await store.scrap(atPath: "Inbox/2026-01-01-0000-ffff.md")
        #expect(scrap.id.stringValue == "8f3a0c2d-5d0f-4c8e-9a51-3c1e7a2b71e4")
    }

    @Test func unreadableScrapIsATypedError() async throws {
        let library = try TemporaryLibrary()
        let store = ScrapStore(root: library.root, clock: FakeWallClock())
        try await store.open()
        try Fixtures.data("unsupported/anchor.md").write(to: library.root.appending(path: "Inbox/anchor.md"))

        await #expect(
            throws: StoreError.unreadable(path: "Inbox/anchor.md", .unsupportedSyntax(line: 5, construct: .anchor))
        ) {
            try await store.scrap(atPath: "Inbox/anchor.md")
        }
    }
}
