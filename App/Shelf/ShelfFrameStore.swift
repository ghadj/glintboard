import CoreGraphics
import Foundation

/// Remembers the shelf's frame per display in `UserDefaults`, keyed by the display's UUID,
/// which stays the same when displays are rearranged or reconnected.
///
/// Frames are stored relative to the display's origin, so a saved frame follows its display
/// when the arrangement changes.
struct ShelfFrameStore {
    private let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    /// The frame last saved on `display`, in global coordinates, or nil if there's none.
    func frame(on display: ShelfDisplay) -> CGRect? {
        guard let values = defaults.array(forKey: key(for: display)) as? [Double], values.count == 4 else {
            return nil
        }
        return CGRect(
            x: display.frame.minX + values[0],
            y: display.frame.minY + values[1],
            width: values[2],
            height: values[3]
        )
    }

    func save(_ frame: CGRect, on display: ShelfDisplay) {
        let values = [
            frame.minX - display.frame.minX,
            frame.minY - display.frame.minY,
            frame.width,
            frame.height,
        ]
        defaults.set(values.map(Double.init), forKey: key(for: display))
    }

    private func key(for display: ShelfDisplay) -> String {
        "ShelfFrame.\(display.id)"
    }
}
