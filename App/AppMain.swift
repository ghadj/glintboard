import AppKit

/// AppKit entry point. The app is a menu bar agent (`LSUIElement`), so there are no scenes
/// or windows at launch; `AppDelegate` builds everything else.
@main
enum AppMain {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        // NSApplication holds its delegate weakly.
        withExtendedLifetime(delegate) {
            app.run()
        }
    }
}
