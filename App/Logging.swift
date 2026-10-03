import os

// One category per area. The subsystem is the bundle identifier, so logs follow the app's
// permanent identity rather than its display name. Captured content is only ever logged
// with `privacy: .private`.

extension Logger {
    /// App lifecycle and composition.
    static let app = Logger(subsystem: AppInfo.bundleIdentifier, category: "app")
    /// Menus, panels, and windows.
    static let ui = Logger(subsystem: AppInfo.bundleIdentifier, category: "ui")
}

extension OSSignposter {
    /// Capture-to-card intervals (NFR-5).
    static let capture = OSSignposter(subsystem: AppInfo.bundleIdentifier, category: "capture")
}
