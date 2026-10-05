import Foundation
import Synchronization

/// Records everything an async stream delivers, and lets a test wait for a value that matches,
/// with a deadline. A missed deadline returns nil, so the test fails instead of hanging, and
/// no test sleeps for a fixed time hoping something has happened.
///
/// Never write a `waitFor` call (or any closure) inside `#expect` or `#require`: store the
/// result in a local and check that. With the Swift compiler in Xcode 27, a closure written
/// inside a macro argument within another closure can get the same symbol as a different
/// closure in that function. A wait then ran another wait's predicate and returned the wrong
/// change, so tests passed without checking anything; when the two closures' types differ the
/// build fails with "function type mismatch". Predicates are evaluated only by the waiting
/// call, over everything recorded so far; a new value just wakes the waiters to look again.
public final class StreamRecorder<Element: Sendable>: Sendable {
    private struct State {
        var values: [Element] = []
        var waiters: [UUID: CheckedContinuation<Void, Never>] = [:]
        var finished = false
    }

    private let state = Mutex(State())
    private let task = Mutex<Task<Void, Never>?>(nil)

    public init(_ stream: AsyncStream<Element>) {
        let listener = Task { [weak self] in
            for await value in stream { self?.receive(value) }
            self?.finish()
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
        let deadline = ContinuousClock.now + .seconds(seconds)
        while true {
            if let match = values.first(where: predicate) { return match }
            guard ContinuousClock.now < deadline, await waitForNextValue(until: deadline) else {
                return values.first(where: predicate)
            }
        }
    }

    /// Suspends until another value arrives (true) or the deadline passes or the stream ends
    /// (false).
    private func waitForNextValue(until deadline: ContinuousClock.Instant) async -> Bool {
        let id = UUID()
        let countBefore = state.withLock { $0.values.count }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let resumeNow = state.withLock { state in
                // Something may have arrived (or the stream ended) since `countBefore`.
                if state.values.count != countBefore || state.finished { return true }
                state.waiters[id] = continuation
                return false
            }
            if resumeNow {
                continuation.resume()
                return
            }
            Task { [weak self] in
                try? await Task.sleep(until: deadline, clock: .continuous)
                self?.wake(id)
            }
        }
        return state.withLock { $0.values.count != countBefore }
    }

    private func receive(_ value: Element) {
        let waiters = state.withLock { state in
            state.values.append(value)
            defer { state.waiters = [:] }
            return Array(state.waiters.values)
        }
        for waiter in waiters { waiter.resume() }
    }

    private func finish() {
        let waiters = state.withLock { state in
            state.finished = true
            defer { state.waiters = [:] }
            return Array(state.waiters.values)
        }
        for waiter in waiters { waiter.resume() }
    }

    private func wake(_ id: UUID) {
        let waiter = state.withLock { $0.waiters.removeValue(forKey: id) }
        waiter?.resume()
    }
}
