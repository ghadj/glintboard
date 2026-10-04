import AppKit
import ScrapCapture

/// The composition root: builds every service and controller once at launch and hands them
/// down through initializers. Nothing else creates services, and there are no singletons;
/// tests build their own pieces with fakes.
@MainActor
final class AppEnvironment {
    let appInfo: AppInfo
    let shelf: ShelfPanelController
    let menuBar: MenuBarController
    let workspace: any WorkspaceClient
    let lastExternalApp: LastExternalAppTracker

    init(appInfo: AppInfo) {
        self.appInfo = appInfo
        workspace = SystemWorkspaceClient()
        lastExternalApp = LastExternalAppTracker(workspace: workspace, ownBundleID: appInfo.bundleIdentifier)
        Task { [lastExternalApp] in await lastExternalApp.start() }
        shelf = ShelfPanelController(
            workspace: workspace,
            ownBundleID: appInfo.bundleIdentifier,
            openedOver: { [lastExternalApp] in lastExternalApp.current },
            frameStore: ShelfFrameStore(defaults: .standard),
            displays: SystemShelfDisplays(),
            // The shelf's SwiftUI content arrives with M1-R17.
            makeContent: { NSView() }
        )
        menuBar = MenuBarController(appInfo: appInfo, shelf: shelf)
    }
}
