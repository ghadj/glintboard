import CoreServices
import Foundation

/// One file-system change FSEvents reported under the watched root.
struct FolderEvent: Sendable, Equatable {
    /// Relative to the root ("" for the root itself).
    let path: String
    /// FSEvents lost events or the root itself changed; the folder needs a full rescan.
    let needsRescan: Bool
    /// The item is a folder that was removed or renamed (moved to the Trash, say). FSEvents
    /// reports only the folder then, not the files inside it.
    var isFolderRemovedOrRenamed: Bool = false
}

/// Watches a folder with FSEvents (file-level events, 300 ms latency, watching the root too).
///
/// The actor runs on its own serial queue, and the FSEvents stream delivers on that same
/// queue, so the C callback re-enters the actor with `assumeIsolated`: no locks, and no
/// `@unchecked Sendable`. Event-driven only; nothing runs while the folder is quiet.
actor FolderWatcher {
    private let queue = DispatchSerialQueue(label: "ScrapStorage.FolderWatcher")
    nonisolated var unownedExecutor: UnownedSerialExecutor { queue.asUnownedSerialExecutor() }

    /// The root with symlinks resolved (FSEvents reports resolved paths, `/private/var/...`).
    private nonisolated let rootPath: String
    private var stream: FSEventStreamRef?
    private var continuation: AsyncStream<[FolderEvent]>.Continuation?

    init(root: URL) {
        rootPath = Self.resolvedPath(of: root)
    }

    /// Starts watching and returns the events, in batches as FSEvents delivers them. The stream
    /// keeps the watcher alive until `stop()`, so a callback never reaches a released watcher.
    func start() throws(StoreError) -> AsyncStream<[FolderEvent]> {
        stop()
        let (events, continuation) = AsyncStream<[FolderEvent]>.makeStream()
        var context = FSEventStreamContext(
            version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
            retain: { info in
                guard let info else { return nil }
                _ = Unmanaged<FolderWatcher>.fromOpaque(info).retain()
                return info
            },
            release: { info in
                guard let info else { return }
                Unmanaged<FolderWatcher>.fromOpaque(info).release()
            },
            copyDescription: nil)
        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagWatchRoot | kFSEventStreamCreateFlagNoDefer)
        let callback: FSEventStreamCallback = { _, info, count, paths, flags, _ in
            guard let info else { return }
            let watcher = Unmanaged<FolderWatcher>.fromOpaque(info).takeUnretainedValue()
            let cPaths = paths.assumingMemoryBound(to: UnsafePointer<CChar>.self)
            var events: [FolderEvent] = []
            for index in 0..<count {
                if let event = watcher.event(path: String(cString: cPaths[index]), flags: flags[index]) {
                    events.append(event)
                }
            }
            // FSEvents delivers on the actor's own queue, so this is already isolated.
            let batch = events
            watcher.assumeIsolated { $0.deliver(batch) }
        }
        guard
            let stream = FSEventStreamCreate(
                kCFAllocatorDefault, callback, &context, [rootPath] as CFArray,
                FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.3, flags)
        else { throw .cannotWatch }
        FSEventStreamSetDispatchQueue(stream, queue)
        guard FSEventStreamStart(stream) else {
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            throw .cannotWatch
        }
        self.stream = stream
        self.continuation = continuation
        return events
    }

    /// Stops watching, ends the event stream, and releases the stream's hold on the watcher.
    func stop() {
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
        stream = nil
        continuation?.finish()
        continuation = nil
    }

    private func deliver(_ events: [FolderEvent]) {
        guard !events.isEmpty else { return }
        continuation?.yield(events)
    }

    /// The event for an absolute path FSEvents reported, or nil if it's outside the root.
    nonisolated func event(path: String, flags: FSEventStreamEventFlags) -> FolderEvent? {
        let rescanFlags = FSEventStreamEventFlags(
            kFSEventStreamEventFlagMustScanSubDirs | kFSEventStreamEventFlagUserDropped
                | kFSEventStreamEventFlagKernelDropped | kFSEventStreamEventFlagRootChanged)
        let needsRescan = flags & rescanFlags != 0
        let removedOrRenamed = FSEventStreamEventFlags(
            kFSEventStreamEventFlagItemRemoved | kFSEventStreamEventFlagItemRenamed)
        let isFolderRemovedOrRenamed =
            flags & FSEventStreamEventFlags(kFSEventStreamEventFlagItemIsDir) != 0 && flags & removedOrRenamed != 0
        let relative: String
        if path == rootPath {
            relative = ""
        } else if path.hasPrefix(rootPath + "/") {
            relative = String(path.dropFirst(rootPath.count + 1))
        } else if needsRescan {
            relative = ""
        } else {
            return nil
        }
        return FolderEvent(path: relative, needsRescan: needsRescan, isFolderRemovedOrRenamed: isFolderRemovedOrRenamed)
    }

    private static func resolvedPath(of url: URL) -> String {
        var path = url.path(percentEncoded: false)
        if let resolved = realpath(path, nil) {
            path = String(cString: resolved)
            free(resolved)
        }
        while path.count > 1, path.hasSuffix("/") { path.removeLast() }
        return path
    }
}
