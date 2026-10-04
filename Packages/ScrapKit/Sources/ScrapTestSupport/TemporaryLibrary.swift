import Foundation

/// A fresh folder for one test, removed when the value is released. `root` is a `Library`
/// folder inside it that doesn't exist yet, as on a first launch.
///
/// The folder's path is fully resolved with `realpath(3)` (`/var` is a link to `/private/var`),
/// so it matches the paths FSEvents reports. Foundation's `resolvingSymlinksInPath()` doesn't
/// do this: it strips a leading `/private` again.
public final class TemporaryLibrary: Sendable {
    public let base: URL
    public let root: URL

    public init() throws {
        let created = FileManager.default.temporaryDirectory
            .appending(path: "ScrapKitTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: created, withIntermediateDirectories: true)
        guard let resolved = realpath(created.path(percentEncoded: false), nil) else {
            throw CocoaError(.fileNoSuchFile)
        }
        defer { free(resolved) }
        base = URL(filePath: String(cString: resolved), directoryHint: .isDirectory)
        root = base.appending(path: "Library", directoryHint: .isDirectory)
    }

    deinit {
        try? FileManager.default.removeItem(at: base)
    }
}
