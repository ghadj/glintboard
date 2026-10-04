import Foundation
import ScrapModel
import ScrapTestSupport
import Testing

@testable import ScrapStorage

struct AtomicWriteTests {
    // MARK: - The seventh acceptance criterion

    /// A write interrupted by a crash leaves only its temporary file behind. The store never
    /// lists or loads that file, and the scrap it was replacing still loads unchanged.
    @Test func leftoverTemporaryFileIsNeverLoaded() async throws {
        let library = try TemporaryLibrary()
        let store = ScrapStore(root: library.root, clock: FakeWallClock())
        try await store.open()
        let inbox = library.root.appending(path: "Inbox")
        let original = try Fixtures.data("design-example.md")
        try original.write(to: inbox.appending(path: "a.md"))
        let halfWritten = original.prefix(original.count / 2)
        try halfWritten.write(to: inbox.appending(path: AtomicFileWriter.temporaryName(for: "a.md")))
        try halfWritten.write(to: inbox.appending(path: AtomicFileWriter.temporaryName(for: "b.md")))

        #expect(try await store.scan().map(\.path) == ["Inbox/a.md"])
        #expect(try await store.scrap(atPath: "Inbox/a.md").title == "2BR on Elm St")
    }

    @Test func leftoverTemporaryFileIsRemovedAtOpen() async throws {
        let library = try TemporaryLibrary()
        try await ScrapStore(root: library.root, clock: FakeWallClock()).open()
        let files = FileManager.default
        let folders = ["Inbox", "Inbox/assets", "Apartment hunt", "Apartment hunt/assets"]
        var leftovers: [String] = []
        for folder in folders {
            try files.createDirectory(at: library.root.appending(path: folder), withIntermediateDirectories: true)
            let path = folder + "/" + AtomicFileWriter.temporaryName(for: "x.md")
            try Data("half".utf8).write(to: library.root.appending(path: path))
            leftovers.append(path)
        }
        // Files that only look similar are someone else's and stay.
        let kept = ["Inbox/.DS_Store", "Inbox/notes.tmp", "Inbox/.draft.tmp"]
        for path in kept { try Data("keep".utf8).write(to: library.root.appending(path: path)) }

        try await ScrapStore(root: library.root, clock: FakeWallClock()).open()

        for path in leftovers {
            #expect(
                !files.fileExists(atPath: library.root.appending(path: path).path(percentEncoded: false)), "\(path)")
        }
        for path in kept {
            #expect(files.fileExists(atPath: library.root.appending(path: path).path(percentEncoded: false)), "\(path)")
        }
    }

    // MARK: - The writer

    @Test func writeReplacesWholeFile() throws {
        let library = try TemporaryLibrary()
        try FileManager.default.createDirectory(
            at: library.base.appending(path: "f"), withIntermediateDirectories: true)
        let target = library.base.appending(path: "f/a.md")
        try Data(String(repeating: "long old content ", count: 100).utf8).write(to: target)

        let replaced = try AtomicFileWriter.write(Data("short".utf8), to: target, label: "f/a.md")
        #expect(replaced)
        #expect(try Data(contentsOf: target) == Data("short".utf8))
        #expect(try contents(of: library.base.appending(path: "f")) == ["a.md"])
    }

    @Test func failedWriteLeavesTargetAndNoTemporaryFile() throws {
        let library = try TemporaryLibrary()
        let folder = library.base.appending(path: "locked")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let target = folder.appending(path: "a.md")
        try Data("old".utf8).write(to: target)
        try setPermissions(0o555, of: folder)
        defer { try? setPermissions(0o755, of: folder) }

        #expect(throws: StoreError.writeFailed(path: "locked/a.md")) {
            try AtomicFileWriter.write(Data("new".utf8), to: target, label: "locked/a.md")
        }
        #expect(try Data(contentsOf: target) == Data("old".utf8))
        #expect(try contents(of: folder) == ["a.md"])
    }

    /// Creating a file that already exists keeps the existing one, without a window in which
    /// a check-then-write could overwrite it.
    @Test func createOnlyKeepsExistingFile() throws {
        let library = try TemporaryLibrary()
        let target = library.base.appending(path: "a.json")
        try Data("existing".utf8).write(to: target)

        let created = try AtomicFileWriter.write(Data("new".utf8), to: target, label: "a.json", mode: .createOnly)
        #expect(!created)
        #expect(try Data(contentsOf: target) == Data("existing".utf8))
        #expect(try contents(of: library.base) == ["a.json"])
    }

    /// A failure after the temporary file was written (here the final rename, because the
    /// target is a folder) still removes the temporary file and leaves the target alone.
    @Test func failureAfterWritingRemovesTemporaryFile() throws {
        let library = try TemporaryLibrary()
        let target = library.base.appending(path: "a.md", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
        try Data("inside".utf8).write(to: target.appending(path: "keep.txt"))

        #expect(throws: StoreError.writeFailed(path: "a.md")) {
            try AtomicFileWriter.write(Data("new".utf8), to: library.base.appending(path: "a.md"), label: "a.md")
        }
        #expect(try contents(of: library.base) == ["a.md"])
        #expect(try contents(of: target) == ["keep.txt"])
    }

    /// A name near the 255-byte limit can still be written: the temporary name shortens its
    /// copy of the name.
    @Test func writesTargetWithLongName() throws {
        let library = try TemporaryLibrary()
        let name = String(repeating: "é", count: 120) + ".md"  // 243 bytes in UTF-8
        let temporary = AtomicFileWriter.temporaryName(for: name)
        #expect(temporary.utf8.count <= 255)
        #expect(AtomicFileWriter.isTemporaryName(temporary))

        try AtomicFileWriter.write(Data("x".utf8), to: library.base.appending(path: name), label: name)
        #expect(try Data(contentsOf: library.base.appending(path: name)) == Data("x".utf8))
        #expect(try contents(of: library.base).count == 1)
    }

    /// An unreadable or missing library isn't an empty one: reconciliation would otherwise
    /// remove every scrap from the index.
    @Test func scanOfMissingRootThrows() async throws {
        let library = try TemporaryLibrary()
        let store = ScrapStore(root: library.root, clock: FakeWallClock())  // never opened
        await #expect(throws: StoreError.readFailed(path: "")) { try await store.scan() }
    }

    @Test func temporaryNamesAreRecognized() {
        let name = AtomicFileWriter.temporaryName(for: "2026-09-30-0915-8f3a.md")
        #expect(name.hasPrefix(".2026-09-30-0915-8f3a.md."))
        #expect(name.hasSuffix(".tmp"))
        #expect(AtomicFileWriter.isTemporaryName(name))
        #expect(!AtomicFileWriter.isTemporaryName("notes.tmp"))
        #expect(!AtomicFileWriter.isTemporaryName(".draft.tmp"))
        #expect(!AtomicFileWriter.isTemporaryName("2026-09-30-0915-8f3a.md"))
    }

    // MARK: - Helpers

    /// Every name in the folder, hidden ones included, so a leftover temporary file shows up.
    private func contents(of folder: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false)).sorted()
    }

    private func setPermissions(_ mode: Int, of url: URL) throws {
        try FileManager.default.setAttributes([.posixPermissions: mode], ofItemAtPath: url.path(percentEncoded: false))
    }
}
