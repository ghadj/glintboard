import Foundation
import os

/// Keeps the index in step with the library: applies each store change to the index, then
/// passes it on. The shelf listens here rather than to the store, so it never shows a change
/// the index doesn't have yet (and search always agrees with the cards).
public actor IndexFollower {
    private let store: ScrapStore
    private let index: ScrapIndex
    private var subscribers: [UUID: AsyncStream<LibraryChange>.Continuation] = [:]
    private var task: Task<Void, Never>?

    public init(store: ScrapStore, index: ScrapIndex) {
        self.store = store
        self.index = index
    }

    /// Every change from now on, after the index has applied it. Each call gets its own stream.
    public func changes() -> AsyncStream<LibraryChange> {
        let (stream, continuation) = AsyncStream<LibraryChange>.makeStream()
        let id = UUID()
        subscribers[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { await self?.removeSubscriber(id) }
        }
        return stream
    }

    /// Starts following the store's changes; call `stop()` when done.
    public func start() async {
        guard task == nil else { return }
        let changes = await store.changes()
        task = Task { [weak self] in
            for await change in changes {
                await self?.handle(change)
            }
        }
    }

    /// Stops following and ends every subscriber's stream.
    public func stop() {
        task?.cancel()
        task = nil
        for subscriber in subscribers.values { subscriber.finish() }
        subscribers = [:]
    }

    private func handle(_ change: LibraryChange) async {
        do {
            try await index.apply(change)
        } catch {
            Logger.index.error("Couldn't apply a change to the index: \(String(describing: error), privacy: .private)")
        }
        if case .problem(let path, _) = change {
            Logger.index.notice("Skipped an unreadable scrap file at \(path, privacy: .private)")
        }
        for subscriber in subscribers.values { subscriber.yield(change) }
    }

    private func removeSubscriber(_ id: UUID) {
        subscribers[id] = nil
    }
}
