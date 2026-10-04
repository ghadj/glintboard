import CoreGraphics

/// The shelf's sizes and placement (`docs/design.md`, "Sizes and spacing"). Pure functions of
/// a display's visible frame, so they're tested without real screens.
enum ShelfGeometry {
    static let defaultSize = CGSize(width: 300, height: 520)
    static let minSize = CGSize(width: 260, height: 320)
    static let maxWidth: CGFloat = 420
    /// Distance from the menu bar and the screen edge on first open (plan Q12).
    static let screenInset: CGFloat = 12

    /// The frame the first time the shelf opens on a display: default size, top-right of the
    /// visible frame (below the menu bar), inset 12 pt.
    static func defaultFrame(in visibleFrame: CGRect) -> CGRect {
        let frame = CGRect(
            x: visibleFrame.maxX - screenInset - defaultSize.width,
            y: visibleFrame.maxY - screenInset - defaultSize.height,
            width: defaultSize.width,
            height: defaultSize.height
        )
        return fitted(frame, in: visibleFrame)
    }

    /// The frame to open with: the saved one if there is one, kept on screen, else the default.
    static func openingFrame(saved: CGRect?, in visibleFrame: CGRect) -> CGRect {
        guard let saved else { return defaultFrame(in: visibleFrame) }
        return fitted(saved, in: visibleFrame)
    }

    /// Width clamped to 260–420, height at least 320.
    static func clampedSize(_ size: CGSize) -> CGSize {
        CGSize(
            width: min(max(size.width, minSize.width), maxWidth),
            height: max(size.height, minSize.height)
        )
    }

    /// Clamps the size, shortens the frame to the screen's height (never below the minimum),
    /// and moves it inside the visible frame. A frame from a display that has since moved,
    /// shrunk or been disconnected comes back on screen. If it can't fit, its top-left stays
    /// visible.
    static func fitted(_ frame: CGRect, in visibleFrame: CGRect) -> CGRect {
        var size = clampedSize(frame.size)
        size.height = max(minSize.height, min(size.height, visibleFrame.height))
        let x = max(min(frame.minX, visibleFrame.maxX - size.width), visibleFrame.minX)
        let y = min(max(frame.minY, visibleFrame.minY), visibleFrame.maxY - size.height)
        return CGRect(origin: CGPoint(x: x, y: y), size: size)
    }
}
