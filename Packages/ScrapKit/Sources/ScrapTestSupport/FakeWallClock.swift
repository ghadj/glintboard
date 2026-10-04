import Foundation
import ScrapModel
import Synchronization

/// A wall clock that only moves when a test moves it.
public final class FakeWallClock: WallClock {
    private let current: Mutex<Date>

    public init(_ start: Date = Date(timeIntervalSince1970: 1_790_690_531)) {
        current = Mutex(start)
    }

    public func now() -> Date {
        current.withLock { $0 }
    }

    public func advance(by seconds: TimeInterval) {
        current.withLock { $0 = $0.addingTimeInterval(seconds) }
    }
}
