import AppKit
import Testing

@testable import App

@MainActor
struct StatusMenuTests {
    private let appInfo = AppInfo(infoDictionary: [
        "CFBundleDisplayName": "Example", "CFBundleIdentifier": "com.example",
    ])

    @Test func menuHasShowShelfSettingsQuitInOrder() {
        let menu = StatusMenu.make(appName: appInfo.displayName, actions: RecordingActions())
        let titles = menu.items.map { $0.isSeparatorItem ? "-" : $0.title }
        #expect(titles == ["Show Shelf", "-", "Settings…", "-", "Quit Example"])
    }

    @Test func settingsHasCommaShortcut() throws {
        let item = try #require(item(titled: "Settings…"))
        #expect(item.keyEquivalent == ",")
        #expect(item.keyEquivalentModifierMask == .command)
    }

    @Test func quitHasQShortcut() throws {
        let item = try #require(item(titled: "Quit Example"))
        #expect(item.keyEquivalent == "q")
        #expect(item.keyEquivalentModifierMask == .command)
    }

    @Test func quitItemTerminatesApp() throws {
        let item = try #require(item(titled: "Quit Example"))
        #expect(item.action == #selector(NSApplication.terminate(_:)))
        #expect(item.target === NSApplication.shared)
    }

    @Test func showShelfAndSettingsCallTheirActions() {
        let actions = RecordingActions()
        let menu = StatusMenu.make(appName: appInfo.displayName, actions: actions)
        menu.performActionForItem(at: 0)
        menu.performActionForItem(at: 2)
        #expect(actions.calls == ["showShelf", "showSettings"])
    }

    /// Each key must be in the compiled catalog; the sentinel comes back when it isn't.
    @Test(arguments: ["Show Shelf", "Settings…", "Quit %@"])
    func menuTitlesAreLocalized(key: String) {
        let missing = "\u{0}missing"
        #expect(Bundle.main.localizedString(forKey: key, value: missing, table: nil) != missing)
    }

    /// AppInfo → MenuBarController → StatusMenu: the in-app half of the rename check.
    @Test func statusItemShowsDisplayName() throws {
        let controller = MenuBarController(appInfo: appInfo, shelf: ShelfPanelController { NSView() })
        defer { NSStatusBar.system.removeStatusItem(controller.statusItem) }
        let button = try #require(controller.statusItem.button)
        #expect(button.toolTip == "Example")
        #expect(button.accessibilityLabel() == "Example")
        #expect(button.image != nil)
        #expect(controller.statusItem.menu?.items.count == 5)
        #expect(controller.statusItem.menu?.items.last?.title == "Quit Example")
    }

    /// For checking titles and shortcuts only: the actions object is freed when this returns,
    /// so the items' (weak) targets are nil. Action tests keep their own `RecordingActions`.
    private func item(titled title: String) -> NSMenuItem? {
        StatusMenu.make(appName: appInfo.displayName, actions: RecordingActions()).item(withTitle: title)
    }
}

@MainActor
private final class RecordingActions: NSObject, StatusMenuActions {
    private(set) var calls: [String] = []

    func showShelf(_ sender: Any?) { calls.append("showShelf") }
    func showSettings(_ sender: Any?) { calls.append("showSettings") }
}
