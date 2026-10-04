import AppKit

/// Shows and closes the shelf panel. The panel is made on first use, and its content exists
/// only while it's open, so a closed shelf holds no views (NFR-2).
@MainActor
final class ShelfPanelController {
    private(set) var panel: ShelfPanel?
    private var content: NSView?
    private let makeContent: () -> NSView

    var isVisible: Bool { panel?.isVisible ?? false }

    /// `makeContent` builds the shelf's views each time it opens.
    init(makeContent: @escaping () -> NSView) {
        self.makeContent = makeContent
    }

    /// Opens the shelf and makes it key, without activating the app.
    func show() {
        let panel = self.panel ?? makePanel()
        if content == nil, let background = panel.contentView {
            let content = makeContent()
            content.frame = background.bounds
            content.autoresizingMask = [.width, .height]
            background.addSubview(content)
            self.content = content
        }
        panel.makeKeyAndOrderFront(nil)
    }

    /// Closes the shelf and releases its content.
    func close() {
        guard let panel else { return }
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
        // Placement and frame memory come with M1-R16.
        panel.center()
        self.panel = panel
        return panel
    }
}
