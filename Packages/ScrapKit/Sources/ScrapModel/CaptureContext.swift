import Foundation

/// Immutable snapshot taken at trigger time, before any of the app's UI appears.
public struct CaptureContext: Sendable, Equatable {
    public let trigger: CaptureTrigger
    public let items: [PasteboardItemSnapshot]
    /// The last external frontmost app.
    public let sourceApp: AppIdentity?
    public let windowTitle: String?
    public let capturedAt: Date

    public init(
        trigger: CaptureTrigger,
        items: [PasteboardItemSnapshot],
        sourceApp: AppIdentity?,
        windowTitle: String?,
        capturedAt: Date
    ) {
        self.trigger = trigger
        self.items = items
        self.sourceApp = sourceApp
        self.windowTitle = windowTitle
        self.capturedAt = capturedAt
    }
}

/// What started a capture.
public enum CaptureTrigger: String, Sendable, CaseIterable {
    case hotkey, drop, screenshot, passive
}

/// One pasteboard item, copied out of `NSPasteboard`.
public struct PasteboardItemSnapshot: Sendable, Equatable {
    /// Every type the item declared, in pasteboard order, including types whose data wasn't
    /// copied (such as privacy markers), so the privacy filter can see them.
    public let types: [String]
    /// Data for the types that were copied, by type identifier.
    public let data: [String: Data]

    public init(types: [String], data: [String: Data]) {
        self.types = types
        self.data = data
    }
}
