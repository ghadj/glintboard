import AppKit
import ScrapCapture
import ScrapModel

/// Shows and closes the shelf panel. The panel is made on first use, and its content exists
/// only while it's open, so a closed shelf holds no views (NFR-2).
///
/// It opens on the display under the pointer, at the frame last used there, and closes on Esc,
/// on Show Shelf while open, or when an app other than the one it opened over becomes active
/// (decision 0018). It listens for activations only while it's open.
@MainActor
final class ShelfPanelController: NSObject, NSWindowDelegate {
    private(set) var panel: ShelfPanel?
    private var content: NSView?
    private var dismissal: Task<Void, Never>?
    private let makeContent: () -> NSView
    private let workspace: any WorkspaceClient
    private let ownBundleID: String
    private let openedOver: () -> AppIdentity?
    private let frameStore: ShelfFrameStore
    private let displays: any ShelfDisplays

    var isVisible: Bool { panel?.isVisible ?? false }

    /// - Parameters:
    ///   - openedOver: the app the shelf opens over, read each time it opens.
    ///   - makeContent: builds the shelf's views each time it opens.
    init(
        workspace: any WorkspaceClient,
        ownBundleID: String,
        openedOver: @escaping () -> AppIdentity?,
        frameStore: ShelfFrameStore,
        displays: any ShelfDisplays,
        makeContent: @escaping () -> NSView
    ) {
        self.workspace = workspace
        self.ownBundleID = ownBundleID
        self.openedOver = openedOver
        self.frameStore = frameStore
        self.displays = displays
        self.makeContent = makeContent
    }

    /// Opens the shelf and makes it key, without activating the app.
    func show() {
        let panel = self.panel ?? makePanel()
        if !panel.isVisible {
            if let display = displays.displayUnderPointer() {
                let frame = ShelfGeometry.openingFrame(saved: frameStore.frame(on: display), in: display.visibleFrame)
                panel.setFrame(frame, display: false)
            }
            closeWhenAnotherAppActivates(openedOver: openedOver())
        }
        if content == nil, let background = panel.contentView {
            let content = makeContent()
            content.frame = background.bounds
            content.autoresizingMask = [.width, .height]
            background.addSubview(content)
            self.content = content
        }
        panel.makeKeyAndOrderFront(nil)
    }

    /// Closes the shelf, remembers its frame, and releases its content.
    func close() {
        dismissal?.cancel()
        dismissal = nil
        guard let panel else { return }
        if panel.isVisible {
            saveFrame(of: panel)
        }
        panel.makeFirstResponder(nil)
        panel.orderOut(nil)
        content?.removeFromSuperview()
        content = nil
    }

    func toggle() {
        if isVisible {
            close()
        } else {
            show()
        }
    }

    /// Whether `activated` becoming active closes a shelf opened over `openedOver`: any app
    /// but that one and this one does. If the app it opened over isn't known, any other app
    /// closes it.
    nonisolated static func closes(
        onActivationOf activated: AppIdentity, openedOver: AppIdentity?, ownBundleID: String
    ) -> Bool {
        activated.bundleID != ownBundleID && activated.bundleID != openedOver?.bundleID
    }

    // MARK: - NSWindowDelegate

    // Saved when a move or resize ends too, so quitting with the shelf open keeps its frame.
    func windowDidMove(_ notification: Notification) {
        guard let panel, panel.isVisible else { return }
        saveFrame(of: panel)
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        guard let panel, panel.isVisible else { return }
        saveFrame(of: panel)
    }

    // MARK: - Private

    private func closeWhenAnotherAppActivates(openedOver: AppIdentity?) {
        dismissal?.cancel()
        // Subscribed before returning, so an activation right after the shelf opens isn't missed.
        let activations = workspace.activations()
        let ownBundleID = ownBundleID
        dismissal = Task { [weak self] in
            for await app in activations {
                guard !Task.isCancelled else { return }
                if Self.closes(onActivationOf: app, openedOver: openedOver, ownBundleID: ownBundleID) {
                    self?.close()
                    return
                }
            }
        }
    }

    private func saveFrame(of panel: ShelfPanel) {
        guard let display = displays.display(showing: panel.frame) else { return }
        frameStore.save(panel.frame, on: display)
    }

    private func makePanel() -> ShelfPanel {
        let panel = ShelfPanel()
        let background = NSVisualEffectView()
        background.material = .popover
        background.blendingMode = .behindWindow
        // Always vibrant: the shelf usually isn't key while you work in the app it opened over
        // (decision 0018).
        background.state = .active
        panel.contentView = background
        panel.onCancel = { [weak self] in self?.close() }
        panel.delegate = self
        self.panel = panel
        return panel
    }
}
