import AppKit
import ScrapModel
import ScrapTestSupport
import SwiftUI
import Testing

@testable import App

@MainActor
struct ShelfPanelTests {
    private let defaults = TestDefaults()
    private let textEdit = AppIdentity(bundleID: "com.apple.TextEdit")
    private let safari = AppIdentity(bundleID: "com.apple.Safari")

    @Test func panelIsNonActivatingFloatingAndCanBecomeKey() {
        let panel = ShelfPanel()
        #expect(panel.styleMask.contains(.nonactivatingPanel))
        #expect(panel.level == .floating)
        #expect(panel.isFloatingPanel)
        #expect(panel.canBecomeKey)
        #expect(!panel.canBecomeMain)
        #expect(!panel.hidesOnDeactivate)
    }

    /// Decision 0018: on every Space and over full-screen apps; "move to active Space" left the
    /// panel behind in the spike.
    @Test func panelJoinsAllSpacesAndFullScreenApps() {
        let behavior = ShelfPanel().collectionBehavior
        #expect(behavior.contains(.canJoinAllSpaces))
        #expect(behavior.contains(.fullScreenAuxiliary))
        #expect(behavior.contains(.ignoresCycle))
        #expect(!behavior.contains(.moveToActiveSpace))
    }

    /// Decision 0018: the system draws the frame and corners; only the title bar is hidden.
    @Test func titleBarIsHiddenButFrameIsTheSystems() {
        let panel = ShelfPanel()
        #expect(panel.styleMask.isSuperset(of: [.titled, .fullSizeContentView, .resizable]))
        #expect(panel.titlebarAppearsTransparent)
        #expect(panel.titleVisibility == .hidden)
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            #expect(panel.standardWindowButton(button)?.isHidden ?? true)
        }
    }

    @Test func contentUsesPopoverMaterial() throws {
        let controller = ShelfPanelController.forTesting(defaults: defaults)
        defer { controller.close() }
        controller.show()

        let effect = try #require(controller.panel?.contentView as? NSVisualEffectView)
        #expect(effect.material == .popover)
        #expect(effect.blendingMode == .behindWindow)
        #expect(effect.state == .active)
    }

    @Test func escapeClosesPanel() throws {
        let controller = ShelfPanelController.forTesting(defaults: defaults)
        defer { controller.close() }
        controller.show()
        let panel = try #require(controller.panel)
        #expect(panel.isVisible)

        panel.cancelOperation(nil)

        #expect(!panel.isVisible)
        #expect(!controller.isVisible)
    }

    @Test func closingReleasesHostingView() {
        weak var content: NSView?
        let controller = ShelfPanelController.forTesting(defaults: defaults) {
            let view = NSHostingView(rootView: Text(verbatim: "content"))
            content = view
            return view
        }
        autoreleasepool { controller.show() }
        #expect(content != nil)

        autoreleasepool { controller.close() }

        #expect(content == nil)
    }

    @Test func toggleShowsThenCloses() {
        let controller = ShelfPanelController.forTesting(defaults: defaults)
        defer { controller.close() }

        controller.toggle()
        #expect(controller.isVisible)
        controller.toggle()
        #expect(!controller.isVisible)
    }

    @Test func panelHasMinAndMaxContentSize() {
        let panel = ShelfPanel()
        #expect(panel.contentMinSize == NSSize(width: 260, height: 320))
        #expect(panel.contentMaxSize.width == 420)
        #expect(panel.contentMaxSize.height >= 10_000)
        // The content fills the frame, so the content limits are the frame's limits.
        let content = NSRect(x: 0, y: 0, width: 300, height: 520)
        #expect(panel.frameRect(forContentRect: content).size == content.size)
    }

    @Test func opensAtDefaultFrameThenWhereItWasLeft() throws {
        let displays = FixedShelfDisplays.mainScreen()
        let display = try #require(displays.underPointer)
        let controller = ShelfPanelController.forTesting(defaults: defaults, displays: displays)
        defer { controller.close() }

        controller.show()
        let panel = try #require(controller.panel)
        #expect(panel.frame == ShelfGeometry.defaultFrame(in: display.visibleFrame))

        let moved = NSRect(
            x: display.visibleFrame.minX + 40, y: display.visibleFrame.minY + 40, width: 380, height: 400)
        panel.setFrame(moved, display: false)
        controller.close()
        panel.setFrame(.zero, display: false)
        controller.show()

        #expect(panel.frame == moved)
        #expect(ShelfFrameStore(defaults: defaults.defaults).frame(on: display) == moved)
    }

    @Test func closesWhenAnotherAppBecomesActive() async throws {
        let workspace = FakeWorkspace(frontmost: textEdit)
        let controller = ShelfPanelController.forTesting(
            workspace: workspace, openedOver: textEdit, defaults: defaults)
        defer { controller.close() }
        controller.show()
        #expect(workspace.subscriberCount == 1)

        // The app it opened over, and this app, leave it open (decision 0018).
        workspace.simulateActivation(of: textEdit)
        workspace.simulateActivation(of: AppIdentity(bundleID: "com.example.shelf"))
        for _ in 0..<100 { await Task.yield() }
        #expect(controller.isVisible)

        workspace.simulateActivation(of: safari)

        #expect(await eventually { !controller.isVisible })
        #expect(await eventually { workspace.subscriberCount == 0 })
    }

    @Test func stopsListeningForActivationsWhenClosed() async {
        let workspace = FakeWorkspace()
        let controller = ShelfPanelController.forTesting(workspace: workspace, defaults: defaults)
        #expect(workspace.subscriberCount == 0)

        controller.show()
        #expect(workspace.subscriberCount == 1)
        controller.close()

        #expect(await eventually { workspace.subscriberCount == 0 })
    }

    /// Decision 0018: clicking or selecting in the app it opened over leaves the shelf open.
    @Test func onlyOtherAppsCloseIt() {
        let own = "com.example.shelf"
        #expect(ShelfPanelController.closes(onActivationOf: safari, openedOver: textEdit, ownBundleID: own))
        #expect(!ShelfPanelController.closes(onActivationOf: textEdit, openedOver: textEdit, ownBundleID: own))
        #expect(
            !ShelfPanelController.closes(
                onActivationOf: AppIdentity(bundleID: own), openedOver: textEdit, ownBundleID: own))
        #expect(ShelfPanelController.closes(onActivationOf: safari, openedOver: nil, ownBundleID: own))
    }

    @Test func showShelfMenuActionOpensPanel() {
        let shelf = ShelfPanelController.forTesting(defaults: defaults)
        let menuBar = MenuBarController(
            appInfo: AppInfo(infoDictionary: ["CFBundleDisplayName": "Example", "CFBundleIdentifier": "com.example"]),
            shelf: shelf
        )
        defer {
            shelf.close()
            NSStatusBar.system.removeStatusItem(menuBar.statusItem)
        }

        menuBar.showShelf(nil)

        #expect(shelf.isVisible)
    }

    @Test func showShelfWhileOpenClosesIt() {
        let shelf = ShelfPanelController.forTesting(defaults: defaults)
        let menuBar = MenuBarController(
            appInfo: AppInfo(infoDictionary: ["CFBundleDisplayName": "Example", "CFBundleIdentifier": "com.example"]),
            shelf: shelf
        )
        defer {
            shelf.close()
            NSStatusBar.system.removeStatusItem(menuBar.statusItem)
        }
        menuBar.showShelf(nil)
        #expect(shelf.isVisible)

        menuBar.showShelf(nil)

        #expect(!shelf.isVisible)
    }
}
