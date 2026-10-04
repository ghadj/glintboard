import Foundation
import Synchronization

/// Records everything an async stream delivers, and lets a test wait for a value that matches,
/// with a deadline. A missed deadline returns nil, so the test fails instead of hanging, and
/// no test sleeps for a fixed time hoping something has happened.
public final class StreamRecorder<Element: Sendable>: Sendable {
    private struct Waiter {
        let predicate: @Sendable (Element) -> Bool
        let continuation: CheckedContinuation<Element?, Never>
    }

    private struct State {
        var values: [Element] = []
        var waiters: [UUID: Waiter] = [:]
    }

    private let state = Mutex(State())
    private let task = Mutex<Task<Void, Never>?>(nil)

    public init(_ stream: AsyncStream<Element>) {
        let listener = Task { [weak self] in
            for await value in stream { self?.receive(value) }
        }
        task.withLock { $0 = listener }
    }

    deinit {
        task.withLock { $0?.cancel() }
    }

    /// Everything received so far, in order.
    public var values: [Element] { state.withLock { $0.values } }

    /// The first value received (before or after this call) that matches, or nil if none has
    /// arrived within `seconds`.
    public func waitFor(within seconds: Double = 5, _ predicate: @escaping @Sendable (Element) -> Bool) async
        -> Element?
    {
        let id = UUID()
        return await withCheckedContinuation { continuation in
            let earlier: Element? = state.withLock { state in
                if let match = state.values.first(where: predicate) { return match }
                state.waiters[id] = Waiter(predicate: predicate, continuation: continuation)
                return nil
            }
            if let earlier {
                continuation.resume(returning: earlier)
                return
            }
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(seconds))
                self?.expire(id)
            }
        }
    }

    private func receive(_ value: Element) {
        let matched: [Waiter] = state.withLock { state in
            state.values.append(value)
            let matching = state.waiters.filter { $0.value.predicate(value) }
            for id in matching.keys { state.waiters[id] = nil }
            return Array(matching.values)
        }
        for waiter in matched { waiter.continuation.resume(returning: value) }
    }

    private func expire(_ id: UUID) {
        let waiter = state.withLock { $0.waiters.removeValue(forKey: id) }
        waiter?.continuation.resume(returning: nil)
    }
}
