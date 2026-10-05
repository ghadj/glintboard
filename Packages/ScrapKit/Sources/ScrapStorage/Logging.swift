import Foundation
import os

// One category per area; the subsystem is the app's bundle identifier. Captured content is only
// ever logged with `privacy: .private`.

extension Logger {
    /// The library folder: writes, cleanup, and watching.
    static let store = Logger(subsystem: Bundle.main.bundleIdentifier ?? "ScrapKit", category: "store")
    /// The search index and keeping it in step with the library.
    static let index = Logger(subsystem: Bundle.main.bundleIdentifier ?? "ScrapKit", category: "index")
}
