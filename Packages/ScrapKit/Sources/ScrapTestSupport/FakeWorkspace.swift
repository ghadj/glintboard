import Foundation
import ScrapCapture
import ScrapModel
import Synchronization

/// A workspace whose activations happen when a test says so.
public final class FakeWorkspace: WorkspaceClient {
    private struct State {
        var frontmost: AppIdentity?
        var subscribers: [UUID: AsyncStream<AppIdentity>.Continuation] = [:]
        var activated: [AppIdentity] = []
        var opened: [URL] = []
    }

    private let state: Mutex<State>

    public init(frontmost: AppIdentity? = nil) {
        state = Mutex(State(frontmost: frontmost))
    }

    /// Makes `app` frontmost and tells every current subscriber.
    public func simulateActivation(of app: AppIdentity) {
        let subscribers = state.withLock { state in
            state.frontmost = app
            return Array(state.subscribers.values)
        }
        for subscriber in subscribers { subscriber.yield(app) }
    }

    /// Apps passed to `activate(_:)`, in order.
    public var activatedApps: [AppIdentity] { state.withLock { $0.activated } }

    /// URLs passed to `open(_:)`, in order.
    public var openedURLs: [URL] { state.withLock { $0.opened } }

    /// How many streams from `activations()` are still being listened to.
    public var subscriberCount: Int { state.withLock { $0.subscribers.count } }

    // MARK: - WorkspaceClient

    public func activations() -> AsyncStream<AppIdentity> {
        let (stream, continuation) = AsyncStream<AppIdentity>.makeStream()
        let id = UUID()
        state.withLock { $0.subscribers[id] = continuation }
        continuation.onTermination = { [weak self] _ in
            self?.state.withLock { _ = $0.subscribers.removeValue(forKey: id) }
        }
        return stream
    }

    public func frontmostApplication() async -> AppIdentity? {
        state.withLock { $0.frontmost }
    }

    public func activate(_ app: AppIdentity) async -> Bool {
        state.withLock { $0.activated.append(app) }
        simulateActivation(of: app)
        return true
    }

    public func open(_ url: URL) async -> Bool {
        state.withLock { $0.opened.append(url) }
        return true
    }
}
