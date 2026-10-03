import AppKit
import os

/// Owns the status item and its menu.
@MainActor
final class MenuBarController: NSObject, StatusMenuActions {
    let statusItem: NSStatusItem

    init(appInfo: AppInfo, statusBar: NSStatusBar = .system) {
        statusItem = statusBar.statusItem(withLength: NSStatusItem.squareLength)
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

    func showShelf(_ sender: Any?) {
        Logger.ui.info("Show Shelf chosen; the shelf arrives in M1")
    }

    func showSettings(_ sender: Any?) {
        Logger.ui.info("Settings chosen; settings arrive in M3")
    }
}
