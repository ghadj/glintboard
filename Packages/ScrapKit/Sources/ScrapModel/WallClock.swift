import Foundation

/// The current date and time. Named to avoid Swift's own `Clock`, which is still used (as
/// `any Clock<Duration>`) for sleeps and timeouts. Lives in ScrapModel so every layer, the
/// store included, can take one; tests inject a fake.
public protocol WallClock: Sendable {
    func now() -> Date
}

/// The system clock.
public struct SystemWallClock: WallClock {
    public init() {}

    public func now() -> Date { Date() }
}
