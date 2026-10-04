import AppKit
import ScrapCapture
import ScrapModel
import ScrapTestSupport

@testable import App

/// A `UserDefaults` suite of its own, removed when this is released, so tests never touch the
/// test host's defaults.
final class TestDefaults {
    let suiteName: String
    let defaults: UserDefaults

    init() {
        let suiteName = "test.shelf.\(UUID().uuidString)"
        self.suiteName = suiteName
        defaults = UserDefaults(suiteName: suiteName)!
    }

    deinit {
        defaults.removePersistentDomain(forName: suiteName)
    }
}

/// Displays fixed by the test. The pointer is on `underPointer`.
@MainActor
final class FixedShelfDisplays: ShelfDisplays {
    var all: [ShelfDisplay]
    var underPointer: ShelfDisplay?

    init(_ displays: [ShelfDisplay]) {
        all = displays
        underPointer = displays.first
    }

    func displayUnderPointer() -> ShelfDisplay? { underPointer }

    func display(showing frame: CGRect) -> ShelfDisplay? {
        all.first { $0.frame.intersects(frame) }
    }

    /// A display with the main screen's frames, so AppKit doesn't move a panel placed on it.
    static func mainScreen(id: String = "main") -> FixedShelfDisplays {
        let screen = NSScreen.main
        return FixedShelfDisplays([
            ShelfDisplay(
                id: id,
                frame: screen?.frame ?? CGRect(x: 0, y: 0, width: 1440, height: 900),
                visibleFrame: screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 875)
            )
        ])
    }
}

extension ShelfPanelController {
    /// A controller with fakes for everything it talks to.
    static func forTesting(
        workspace: FakeWorkspace = FakeWorkspace(),
        openedOver: AppIdentity? = nil,
        defaults: TestDefaults,
        displays: FixedShelfDisplays = .mainScreen(),
        makeContent: @escaping () -> NSView = { NSView() }
    ) -> ShelfPanelController {
        ShelfPanelController(
            workspace: workspace,
            ownBundleID: "com.example.shelf",
            openedOver: { openedOver },
            frameStore: ShelfFrameStore(defaults: defaults.defaults),
            displays: displays,
            makeContent: makeContent
        )
    }
}

/// Lets other main-actor work run until `condition` holds, failing after 5 s. It yields rather
/// than sleeping, so it returns as soon as the condition holds.
@MainActor
func eventually(_ condition: () -> Bool) async -> Bool {
    let deadline = ContinuousClock.now + .seconds(5)
    while !condition() {
        if ContinuousClock.now >= deadline { return false }
        await Task.yield()
    }
    return true
}
