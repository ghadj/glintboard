import AppKit
import SwiftUI
import Testing

@testable import App

@MainActor
struct ShelfPanelTests {
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
        let controller = ShelfPanelController { NSView() }
        defer { controller.close() }
        controller.show()

        let effect = try #require(controller.panel?.contentView as? NSVisualEffectView)
        #expect(effect.material == .popover)
        #expect(effect.blendingMode == .behindWindow)
        #expect(effect.state == .active)
    }

    @Test func escapeClosesPanel() throws {
        let controller = ShelfPanelController { NSView() }
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
        let controller = ShelfPanelController {
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
        let controller = ShelfPanelController { NSView() }
        defer { controller.close() }

        controller.toggle()
        #expect(controller.isVisible)
        controller.toggle()
        #expect(!controller.isVisible)
    }

    @Test func showShelfMenuActionOpensPanel() {
        let shelf = ShelfPanelController { NSView() }
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
}
