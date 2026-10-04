import Foundation
import ScrapModel
import os

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

    /// Creates the root and the Inbox, with its `.collection.json`, if they're missing, and
    /// removes temporary files left by writes a crash interrupted. Existing files are left as
    /// they are.
    public func open() throws(StoreError) {
        try createFolder(root, path: "")
        let inbox = folder(for: .inbox)
        try createFolder(inbox, path: CollectionName.inbox.rawValue)
        let collectionFile = inbox.appending(path: LibraryLayout.collectionFileName)
        // Checked first, so a normal launch writes nothing; the create-only write still never
        // replaces a file that appeared in between.
        if !files.fileExists(atPath: collectionFile.path(percentEncoded: false)) {
            let info = CollectionInfo(name: CollectionName.inbox.rawValue, order: 0, created: clock.now())
            try AtomicFileWriter.write(
                try CollectionFile.encode(info), to: collectionFile, label: relativePath(of: collectionFile),
                mode: .createOnly)
        }
        removeLeftoverTemporaryFiles()
    }

    /// Temporary files in collection folders and their `assets/` folders are what a write
    /// interrupted by a crash leaves behind; the files they were replacing are intact.
    private func removeLeftoverTemporaryFiles() {
        var removed = 0
        // Best effort: the root was just created or listed, and a leftover that stays is harmless.
        for collection in (try? collectionFolders()) ?? [] {
            for folder in [collection, collection.appending(path: LibraryLayout.assetsFolderName)] {
                let names = (try? files.contentsOfDirectory(atPath: folder.path(percentEncoded: false))) ?? []
                for name in names where AtomicFileWriter.isTemporaryName(name) {
                    if (try? files.removeItem(at: folder.appending(path: name))) != nil { removed += 1 }
                }
            }
        }
        if removed > 0 {
            Logger.store.notice("Removed \(removed) temporary files left by interrupted writes")
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

    /// Every scrap file: the `.md` files directly inside collection folders, sorted by path.
    /// Hidden files (temporary files among them) and other folders' contents aren't included.
    public func scan() throws(StoreError) -> [ScrapFileInfo] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey]
        var result: [ScrapFileInfo] = []
        for collection in try collectionFolders() {
            let entries: [URL]
            do {
                entries = try files.contentsOfDirectory(
                    at: collection, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])
            } catch {
                throw .readFailed(path: relativePath(of: collection))
            }
            for entry in entries where entry.pathExtension.lowercased() == "md" {
                guard let values = try? entry.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else {
                    continue
                }
                result.append(
                    ScrapFileInfo(
                        path: relativePath(of: entry), modified: values.contentModificationDate ?? .distantPast,
                        size: values.fileSize ?? 0))
            }
        }
        return result.sorted { $0.path < $1.path }
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

    /// Folders under the root that are collections: not hidden, and valid collection names.
    /// Throws when the root can't be listed, so callers never mistake an unreadable or missing
    /// library for an empty one.
    private func collectionFolders() throws(StoreError) -> [URL] {
        let entries: [URL]
        do {
            entries = try files.contentsOfDirectory(
                at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
        } catch {
            throw .readFailed(path: "")
        }
        return entries.filter { entry in
            (try? entry.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
                && CollectionName(entry.lastPathComponent) != nil
        }
    }

    private func createFolder(_ url: URL, path: String) throws(StoreError) {
        do {
            try files.createDirectory(at: url, withIntermediateDirectories: true)
        } catch {
            throw .cannotCreateFolder(path: path)
        }
    }
}
