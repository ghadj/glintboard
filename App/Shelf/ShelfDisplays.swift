import AppKit

/// A display as the shelf sees it: a stable identifier and its frames in global coordinates.
struct ShelfDisplay: Equatable {
    /// The display's UUID, stable across rearrangements and reconnections.
    var id: String
    var frame: CGRect
    /// The frame minus the menu bar and the Dock.
    var visibleFrame: CGRect
}

/// Where the shelf opens and which display it's on. Tests use fixed displays.
@MainActor
protocol ShelfDisplays {
    /// The display under the pointer, where the shelf opens (plan Q12).
    func displayUnderPointer() -> ShelfDisplay?
    /// The display showing most of `frame`.
    func display(showing frame: CGRect) -> ShelfDisplay?
}

/// `ShelfDisplays` backed by `NSScreen`.
struct SystemShelfDisplays: ShelfDisplays {
    func displayUnderPointer() -> ShelfDisplay? {
        let pointer = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(pointer, $0.frame, false) } ?? NSScreen.main
        return screen.flatMap(ShelfDisplay.init(_:))
    }

    func display(showing frame: CGRect) -> ShelfDisplay? {
        let screen = NSScreen.screens.max { area($0.frame.intersection(frame)) < area($1.frame.intersection(frame)) }
        // A frame on no screen belongs to no display.
        guard let screen, area(screen.frame.intersection(frame)) > 0 else { return nil }
        return ShelfDisplay(screen)
    }

    private func area(_ rect: CGRect) -> CGFloat {
        rect.isNull ? 0 : rect.width * rect.height
    }
}

extension ShelfDisplay {
    /// Nil if the screen has no display number or UUID.
    @MainActor
    init?(_ screen: NSScreen) {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
            let uuid = CGDisplayCreateUUIDFromDisplayID(number.uint32Value)?.takeRetainedValue(),
            let string = CFUUIDCreateString(nil, uuid)
        else { return nil }
        self.init(id: string as String, frame: screen.frame, visibleFrame: screen.visibleFrame)
    }
}
