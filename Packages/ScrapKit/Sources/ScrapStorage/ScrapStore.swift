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
            let scrap = try FrontmatterCodec.decode(data)
            paths[scrap.id] = relativePath
            return scrap
        } catch {
            throw .unreadable(path: relativePath, error)
        }
    }

    // MARK: - Writing scraps

    /// Where each scrap's file is, relative to the root, as learned from reads and creates.
    private var paths: [ScrapID: String] = [:]

    /// The file of a scrap this store has read or created.
    public func path(of id: ScrapID) throws(StoreError) -> String {
        guard let path = paths[id] else { throw .unknownScrap(id) }
        return path
    }

    /// Writes a new scrap file in `collection`, named by capture time and id. This is the only
    /// call that writes a body: captured text is immutable afterwards. It never replaces a file;
    /// a name that's taken gets `-2`, `-3`, and so on.
    @discardableResult
    public func create(_ draft: ScrapDraft, in collection: CollectionName) throws(StoreError) -> Scrap {
        // One file per id (the id is authoritative); a draft reusing a known id is a bug.
        guard paths[draft.id] == nil else { throw .idInUse(draft.id) }
        let folder = folder(for: collection)
        try createFolder(folder, path: collection.rawValue)
        let created = Self.wholeSeconds(draft.created)
        let scrap = Scrap(
            id: draft.id, kind: draft.kind, title: draft.title, body: draft.body, board: draft.board,
            created: created, updated: created, reference: draft.reference)
        let data = Data(FrontmatterCodec.encode(scrap).utf8)

        let preferred = LibraryLayout.fileName(created: created, id: draft.id)
        var taken = Set((try? files.contentsOfDirectory(atPath: folder.path(percentEncoded: false))) ?? [])
        while true {
            let name = LibraryLayout.uniqueName(preferred, existing: taken)
            let path = collection.rawValue + "/" + name
            if try AtomicFileWriter.write(data, to: folder.appending(path: name), label: path, mode: .createOnly) {
                paths[scrap.id] = path
                didWrite(scrap, data: data, path: path)
                return scrap
            }
            // Created by someone else since the folder was listed: try the next suffix. Tests
            // can't stage this race without a fake writer, so it's covered by reasoning only.
            taken.insert(name)
        }
    }

    /// Applies `edits` to the scrap's file as it is on disk now. Only frontmatter changes; the
    /// body, including any edit made in another editor, is written back exactly as it was read.
    /// Title and note edits count as edits for `updated`; pinning, board order, and the
    /// system's reference and asset updates don't.
    @discardableResult
    public func update(_ id: ScrapID, _ edits: [ScrapEdit]) throws(StoreError) -> Scrap {
        let path = try self.path(of: id)
        var scrap = try self.scrap(atPath: path)
        guard scrap.id == id else {
            // The file now belongs to another scrap (replaced or renamed outside the app).
            paths[id] = nil
            throw .unknownScrap(id)
        }
        // Nothing to change: leave the file exactly as another editor may have formatted it.
        guard !edits.isEmpty else { return scrap }
        let now = Self.wholeSeconds(clock.now())
        for edit in edits {
            switch edit {
            case .title(let title):
                scrap.title = title
                scrap.updated = now
            case .note(let text):
                scrap.note = text.map { Note(text: $0, updated: now) }
                scrap.updated = now
            case .pinned(let pinned): scrap.pinned = pinned
            case .board(let rank): scrap.board = rank
            case .reference(let reference): scrap.reference = reference
            case .asset(let asset): scrap.asset = asset
            }
        }
        let data = Data(FrontmatterCodec.encode(scrap).utf8)
        try AtomicFileWriter.write(data, to: root.appending(path: path), label: path)
        didWrite(scrap, data: data, path: path)
        return scrap
    }

    // MARK: - Changes and watching

    /// The store's own recent writes, so their FSEvents echoes aren't mistaken for edits.
    private var ledger = WriteLedger()
    private var subscribers: [UUID: AsyncStream<LibraryChange>.Continuation] = [:]
    private var watcher: FolderWatcher?
    private var watchTask: Task<Void, Never>?

    /// Every change from now on: the store's own writes (`.saved`) and, while watching, changes
    /// made outside the app. Each call gets its own stream; it ends when the caller stops
    /// listening.
    public func changes() -> AsyncStream<LibraryChange> {
        let (stream, continuation) = AsyncStream<LibraryChange>.makeStream()
        let id = UUID()
        subscribers[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { await self?.removeSubscriber(id) }
        }
        return stream
    }

    /// Starts reporting changes made outside the app. Event-driven: nothing runs while the folder
    /// is quiet.
    /// Call `stopWatching()` when done: the FSEvents stream keeps its watcher alive until then.
    public func startWatching() async throws(StoreError) {
        guard watcher == nil else { return }
        // Claimed before the await, so an overlapping call returns instead of starting a
        // second watcher.
        let watcher = FolderWatcher(root: root)
        self.watcher = watcher
        let events: AsyncStream<[FolderEvent]>
        do throws(StoreError) {
            events = try await watcher.start()
        } catch {
            self.watcher = nil
            throw error
        }
        watchTask = Task { [weak self] in
            for await batch in events {
                await self?.handle(batch)
            }
        }
    }

    public func stopWatching() async {
        watchTask?.cancel()
        watchTask = nil
        await watcher?.stop()
        watcher = nil
    }

    private func removeSubscriber(_ id: UUID) {
        subscribers[id] = nil
    }

    private func emit(_ change: LibraryChange) {
        for subscriber in subscribers.values { subscriber.yield(change) }
    }

    private func didWrite(_ scrap: Scrap, data: Data, path: String) {
        ledger.record(path: path, hash: Fingerprint.data(data).rawValue, at: clock.now())
        emit(.saved(scrap, file: fileInfo(at: path, size: data.count)))
    }

    /// The file's modification date and size as they are now, read the same way `scan()` reads
    /// them, so reconciliation can compare the two exactly. `size` is the fallback if the file
    /// can't be inspected.
    private func fileInfo(at path: String, size: Int) -> ScrapFileInfo {
        let values = try? root.appending(path: path).resourceValues(forKeys: [
            .contentModificationDateKey, .fileSizeKey,
        ])
        return ScrapFileInfo(
            path: path, modified: values?.contentModificationDate ?? .distantPast, size: values?.fileSize ?? size)
    }

    /// One batch of FSEvents. Each path is handled once, by what the file holds now.
    private func handle(_ batch: [FolderEvent]) {
        // A collection folder renamed or removed (moved to the Trash, say) is reported as the
        // folder alone, not its files; only a rescan can tell what changed.
        let collectionFolderGone = batch.contains { $0.isFolderRemovedOrRenamed && !$0.path.contains("/") }
        if batch.contains(where: \.needsRescan) || collectionFolderGone { emit(.rescanNeeded) }
        var seen: Set<String> = []
        for event in batch where seen.insert(event.path).inserted {
            handleChange(at: event.path)
        }
    }

    private func handleChange(at path: String) {
        guard Self.isScrapPath(path) else { return }
        let url = root.appending(path: path)
        guard let data = try? Data(contentsOf: url) else {
            if !files.fileExists(atPath: url.path(percentEncoded: false)) {
                let id = paths.first(where: { $0.value == path })?.key
                if let id { paths[id] = nil }
                emit(.removed(path: path, id: id))
            }
            return
        }
        // The store's own write coming back from FSEvents: not a change.
        if ledger.isEcho(path: path, hash: Fingerprint.data(data).rawValue, now: clock.now()) { return }
        do throws(CodecError) {
            let scrap = try FrontmatterCodec.decode(data)
            if let known = paths[scrap.id], known != path,
                files.fileExists(atPath: root.appending(path: known).path(percentEncoded: false))
            {
                // A copy of a scrap whose file is still there (made in Finder, say). The id stays
                // with the original; reconciliation (M1-R10) gives the copy a fresh id.
                Logger.store.notice("Copy of a known scrap at \(path, privacy: .private); left for reconciliation")
                return
            }
            paths[scrap.id] = path
            emit(.updated(scrap, file: fileInfo(at: path, size: data.count)))
        } catch {
            Logger.store.error("Can't read \(path, privacy: .private): \(String(describing: error), privacy: .private)")
            emit(.problem(path: path, error))
        }
    }

    /// A scrap file: `<collection>/<name>.md` directly in a collection folder, not hidden.
    /// Everything else (`.trash/`, the index, `assets/`, temporary and other files) is ignored.
    private static func isScrapPath(_ path: String) -> Bool {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2, CollectionName(String(parts[0])) != nil else { return false }
        let name = parts[1]
        return !name.hasPrefix(".") && name.lowercased().hasSuffix(".md")
    }

    /// Frontmatter stores whole seconds, so in-memory scraps do too.
    private static func wholeSeconds(_ date: Date) -> Date {
        Date(timeIntervalSince1970: date.timeIntervalSince1970.rounded(.down))
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
