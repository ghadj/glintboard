import CoreGraphics
import Testing

@testable import App

struct ShelfGeometryTests {
    /// A 1440 × 900 display with a 25 pt menu bar.
    private let laptop = ShelfDisplay(
        id: "laptop",
        frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
        visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 875)
    )
    /// A 1920 × 1080 display to the left of the laptop, its menu bar hidden.
    private let external = ShelfDisplay(
        id: "external",
        frame: CGRect(x: -1920, y: 100, width: 1920, height: 1080),
        visibleFrame: CGRect(x: -1920, y: 100, width: 1920, height: 1080)
    )

    @Test func defaultFrameIs300By520AtTopRight() {
        #expect(
            ShelfGeometry.defaultFrame(in: laptop.visibleFrame)
                == CGRect(x: 1440 - 12 - 300, y: 875 - 12 - 520, width: 300, height: 520))
        #expect(
            ShelfGeometry.defaultFrame(in: external.visibleFrame)
                == CGRect(x: -12 - 300, y: 1180 - 12 - 520, width: 300, height: 520))
        #expect(
            ShelfGeometry.openingFrame(saved: nil, in: laptop.visibleFrame)
                == ShelfGeometry.defaultFrame(in: laptop.visibleFrame))
    }

    @Test func widthIsClampedTo260Through420() {
        let cases: [(width: CGFloat, expected: CGFloat)] = [(200, 260), (260, 260), (333, 333), (420, 420), (500, 420)]
        for (width, expected) in cases {
            let clamped = ShelfGeometry.clampedSize(CGSize(width: width, height: 520)).width
            #expect(clamped == expected, "width \(width)")
            let saved = CGRect(x: 100, y: 100, width: width, height: 520)
            let opened = ShelfGeometry.openingFrame(saved: saved, in: laptop.visibleFrame).width
            #expect(opened == expected, "width \(width)")
        }
    }

    @Test func heightIsAtLeast320() {
        #expect(ShelfGeometry.clampedSize(CGSize(width: 300, height: 100)).height == 320)
        #expect(ShelfGeometry.clampedSize(CGSize(width: 300, height: 800)).height == 800)
        let short = CGRect(x: 100, y: 100, width: 300, height: 100)
        #expect(ShelfGeometry.openingFrame(saved: short, in: laptop.visibleFrame).height == 320)
        // Taller than the screen: shortened to fit, but never below 320.
        let tall = CGRect(x: 100, y: 0, width: 300, height: 2000)
        #expect(ShelfGeometry.openingFrame(saved: tall, in: laptop.visibleFrame).height == 875)
        let tiny = CGRect(x: 0, y: 0, width: 800, height: 200)
        #expect(ShelfGeometry.defaultFrame(in: tiny).height == 320)
    }

    @Test func frameIsRememberedPerDisplay() {
        let defaults = TestDefaults()
        let store = ShelfFrameStore(defaults: defaults.defaults)
        let onLaptop = CGRect(x: 40, y: 60, width: 280, height: 400)
        let onExternal = CGRect(x: -1000, y: 300, width: 400, height: 700)
        #expect(store.frame(on: laptop) == nil)

        store.save(onLaptop, on: laptop)
        store.save(onExternal, on: external)

        // Read back by a new store, as on the next launch.
        let reopened = ShelfFrameStore(defaults: defaults.defaults)
        #expect(reopened.frame(on: laptop) == onLaptop)
        #expect(reopened.frame(on: external) == onExternal)

        // The arrangement changes: the external display moves above the laptop. Same UUID, so
        // the frame follows it.
        var moved = external
        moved.frame.origin = CGPoint(x: 0, y: 900)
        moved.visibleFrame.origin = CGPoint(x: 0, y: 900)
        #expect(reopened.frame(on: moved) == CGRect(x: 920, y: 1100, width: 400, height: 700))
    }

    @Test func offscreenFrameIsMovedOnScreen() {
        let visible = laptop.visibleFrame
        let frames = [
            // Past the right edge.
            CGRect(x: 5000, y: 100, width: 300, height: 520),
            // Where a disconnected display on the left used to be.
            CGRect(x: -1500, y: 400, width: 300, height: 520),
            // Under the menu bar.
            CGRect(x: 200, y: 700, width: 300, height: 520),
            // Below the bottom edge.
            CGRect(x: 200, y: -300, width: 300, height: 520),
        ]
        for frame in frames {
            let opened = ShelfGeometry.openingFrame(saved: frame, in: visible)
            #expect(visible.contains(opened), "\(frame) opened at \(opened)")
            #expect(opened.size == frame.size)
        }
        // A frame already on screen stays where it is.
        let onScreen = CGRect(x: 200, y: 100, width: 300, height: 520)
        #expect(ShelfGeometry.openingFrame(saved: onScreen, in: visible) == onScreen)
    }
}
