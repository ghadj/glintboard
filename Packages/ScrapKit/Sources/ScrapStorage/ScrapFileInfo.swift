import Foundation

/// A scrap file found on disk: what reconciliation compares with the index.
public struct ScrapFileInfo: Sendable, Equatable {
    /// Relative to the library root, for example `Inbox/2026-09-30-0915-8f3a.md`.
    public let path: String
    public let modified: Date
    public let size: Int

    public init(path: String, modified: Date, size: Int) {
        self.path = path
        self.modified = modified
        self.size = size
    }
}
