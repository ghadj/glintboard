import AppKit

/// What the status menu's items do, other than Quit.
@MainActor
@objc protocol StatusMenuActions {
    func showShelf(_ sender: Any?)
    func showSettings(_ sender: Any?)
}

enum StatusMenu {
    /// Show Shelf, Settings… (⌘,), and Quit <name> (⌘Q). Menu items hold their target
    /// weakly, so the caller keeps `actions` alive.
    @MainActor
    static func make(appName: String, actions: StatusMenuActions) -> NSMenu {
        let menu = NSMenu()

        let showShelf = NSMenuItem(
            title: String(localized: "Show Shelf", comment: "Status menu item that opens the shelf panel."),
            action: #selector(StatusMenuActions.showShelf(_:)),
            keyEquivalent: ""
        )
        showShelf.target = actions
        menu.addItem(showShelf)

        menu.addItem(.separator())

        let settings = NSMenuItem(
            title: String(localized: "Settings…", comment: "Status menu item that opens Settings."),
            action: #selector(StatusMenuActions.showSettings(_:)),
            keyEquivalent: ","
        )
        settings.target = actions
        menu.addItem(settings)

        menu.addItem(.separator())

        let quit = NSMenuItem(
            title: String(
                localized: "Quit \(appName)",
                comment: "Status menu item that quits the app. %@ is the app's display name (AppInfo.displayName)."
            ),
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        quit.target = NSApplication.shared
        menu.addItem(quit)

        return menu
    }
}
