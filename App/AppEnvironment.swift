/// The composition root: builds every service and controller once at launch and hands them
/// down through initializers. Nothing else creates services, and there are no singletons;
/// tests build their own pieces with fakes.
@MainActor
final class AppEnvironment {
    let appInfo: AppInfo
    let menuBar: MenuBarController

    init(appInfo: AppInfo) {
        self.appInfo = appInfo
        menuBar = MenuBarController(appInfo: appInfo)
    }
}
