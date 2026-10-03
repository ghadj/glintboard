import AppKit
import os

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var environment: AppEnvironment?

    func applicationDidFinishLaunching(_ notification: Notification) {
        environment = AppEnvironment(appInfo: .main)
        // Notice level so it's kept in the log store: NFR-4 (launch to menu bar icon) is
        // measured from `open` to this line's timestamp (docs/perf.md).
        Logger.app.notice("Launched: status item installed")
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }
}
