import AppKit

/// The shelf's window: a floating panel that takes the keyboard without activating the app, so
/// the app you came from keeps the menu bar (decision 0018).
///
/// It keeps the system's window frame, so macOS draws its corners and shadow and handles edge
/// resizing; only the title bar is hidden. It shows on every Space and over full-screen apps.
final class ShelfPanel: NSPanel {
    /// Called for Esc (`cancelOperation(_:)`), whichever view in the panel has focus.
    var onCancel: (() -> Void)?

    init() {
        super.init(
            contentRect: NSRect(origin: .zero, size: ShelfGeometry.defaultSize),
            // Set at creation (decision 0018).
            styleMask: [.nonactivatingPanel, .titled, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )
        level = .floating
        isFloatingPanel = true
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = false
        isReleasedWhenClosed = false
        // The content fills the frame (full-size content view), so these bound the frame too.
        contentMinSize = ShelfGeometry.minSize
        contentMaxSize = NSSize(width: ShelfGeometry.maxWidth, height: .greatestFiniteMagnitude)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            standardWindowButton(button)?.isHidden = true
        }
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}
