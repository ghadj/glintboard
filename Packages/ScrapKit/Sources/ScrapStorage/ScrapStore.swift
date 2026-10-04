import Foundation
import ScrapModel

/// The library folder: collections as folders, scraps as Markdown files. The only type that
/// touches the folder. Paths it takes and reports are relative to `root`.
public actor ScrapStore {
    public let root: URL
    private let clock: any WallClock
    private let files = FileManager.default

    public init(root: URL, clock: any WallClock) {
        // As a directory URL, so its path ends in "/" and relative paths never start with one.
        self.root = URL(filePath: root.path(percentEncoded: false), directoryHint: .isDirectory)
        self.clock = clock
    }

    /// Creates the root and the Inbox, with its `.collection.json`, if they're missing.
    /// Existing files are left as they are.
    public func open() throws(StoreError) {
        try createFolder(root, path: "")
        let inbox = folder(for: .inbox)
        try createFolder(inbox, path: CollectionName.inbox.rawValue)
        let collectionFile = inbox.appending(path: LibraryLayout.collectionFileName)
        if !files.fileExists(atPath: collectionFile.path(percentEncoded: false)) {
            let info = CollectionInfo(name: CollectionName.inbox.rawValue, order: 0, created: clock.now())
            try write(try CollectionFile.encode(info), to: collectionFile, path: relativePath(of: collectionFile))
        }
    }

    /// The collections, by display order, then name. A folder without a readable
    /// `.collection.json` (one made in Finder, say) is listed last, dated by the folder.
    public func collections() throws(StoreError) -> [CollectionInfo] {
        let entries: [URL]
        do {
            entries = try files.contentsOfDirectory(
                at: root, includingPropertiesForKeys: [.isDirectoryKey, .creationDateKey], options: [.skipsHiddenFiles])
        } catch {
            throw .readFailed(path: "")
        }
        var result: [CollectionInfo] = []
        for entry in entries {
            let values = try? entry.resourceValues(forKeys: [.isDirectoryKey, .creationDateKey])
            guard values?.isDirectory == true, let name = CollectionName(entry.lastPathComponent) else { continue }
            let file = entry.appending(path: LibraryLayout.collectionFileName)
            if let data = try? Data(contentsOf: file), let info = try? CollectionFile.decode(data, name: name.rawValue)
            {
                result.append(info)
            } else {
                result.append(
                    CollectionInfo(name: name.rawValue, order: .max, created: values?.creationDate ?? .distantPast))
            }
        }
        return result.sorted { ($0.order, $0.name) < ($1.order, $1.name) }
    }

    /// Reads the scrap file at `relativePath`. Its id comes from its frontmatter.
    public func scrap(atPath relativePath: String) throws(StoreError) -> Scrap {
        let data: Data
        do {
            data = try Data(contentsOf: root.appending(path: relativePath))
        } catch {
            throw .readFailed(path: relativePath)
        }
        do throws(CodecError) {
            return try FrontmatterCodec.decode(data)
        } catch {
            throw .unreadable(path: relativePath, error)
        }
    }

    // MARK: - Helpers

    private func folder(for collection: CollectionName) -> URL {
        root.appending(path: collection.rawValue, directoryHint: .isDirectory)
    }

    private func relativePath(of url: URL) -> String {
        let rootPath = root.path(percentEncoded: false)
        let path = url.path(percentEncoded: false)
        return path.hasPrefix(rootPath) ? String(path.dropFirst(rootPath.count)) : path
    }

    private func createFolder(_ url: URL, path: String) throws(StoreError) {
        do {
            try files.createDirectory(at: url, withIntermediateDirectories: true)
        } catch {
            throw .cannotCreateFolder(path: path)
        }
    }

    // Replaced by the atomic writer in M1-R6.
    private func write(_ data: Data, to url: URL, path: String) throws(StoreError) {
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            throw .writeFailed(path: path)
        }
    }
}
