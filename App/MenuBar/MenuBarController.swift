import AppKit
import os

/// Owns the status item and its menu.
@MainActor
final class MenuBarController: NSObject, StatusMenuActions {
    let statusItem: NSStatusItem
    private let shelf: ShelfPanelController

    init(appInfo: AppInfo, shelf: ShelfPanelController, statusBar: NSStatusBar = .system) {
        statusItem = statusBar.statusItem(withLength: NSStatusItem.squareLength)
        self.shelf = shelf
        super.init()
        if let button = statusItem.button {
            // Placeholder icon until the app icon exists.
            let image = NSImage(systemSymbolName: "rectangle.stack", accessibilityDescription: appInfo.displayName)
            image?.isTemplate = true
            button.image = image
            button.toolTip = appInfo.displayName
            button.setAccessibilityLabel(appInfo.displayName)
        }
        statusItem.menu = StatusMenu.make(appName: appInfo.displayName, actions: self)
    }

    /// Opens the shelf, or closes it if it's open (decision 0018).
    func showShelf(_ sender: Any?) {
        shelf.toggle()
    }

    func showSettings(_ sender: Any?) {
        Logger.ui.info("Settings chosen; settings arrive in M3")
    }
}
