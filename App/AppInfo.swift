import Foundation

/// The app's display name and bundle identifier, read from Info.plist.
///
/// The product name lives only in `Config/Branding.xcconfig`. Code reads it through
/// `AppInfo.displayName` and never writes it as a literal; see "Naming and branding" in
/// `docs/architecture.md`.
struct AppInfo: Equatable, Sendable {
    let displayName: String
    let bundleIdentifier: String

    init(infoDictionary: [String: Any]) {
        displayName =
            infoDictionary["CFBundleDisplayName"] as? String
            ?? infoDictionary["CFBundleName"] as? String
            ?? ""
        bundleIdentifier = infoDictionary["CFBundleIdentifier"] as? String ?? ""
    }

    init(bundle: Bundle) {
        self.init(infoDictionary: bundle.infoDictionary ?? [:])
    }

    /// The running app's values. A Debug build with a broken Info.plist stops here instead of
    /// showing blank titles and logging under an empty subsystem.
    static let main: AppInfo = {
        let info = AppInfo(bundle: .main)
        assert(
            !info.displayName.isEmpty && !info.bundleIdentifier.isEmpty,
            "Info.plist is missing CFBundleDisplayName/CFBundleName or CFBundleIdentifier"
        )
        return info
    }()

    static var displayName: String { main.displayName }
    static var bundleIdentifier: String { main.bundleIdentifier }
}
