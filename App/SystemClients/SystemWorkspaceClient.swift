import AppKit
import ScrapCapture
import ScrapModel

/// `WorkspaceClient` backed by `NSWorkspace`.
struct SystemWorkspaceClient: WorkspaceClient {
    func activations() -> AsyncStream<AppIdentity> {
        let (stream, continuation) = AsyncStream<AppIdentity>.makeStream()
        let observer = ActivationObserver(continuation: continuation)
        NSWorkspace.shared.notificationCenter.addObserver(
            observer,
            selector: #selector(ActivationObserver.applicationDidActivate(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
        // The termination handler keeps the observer alive (the notification center doesn't)
        // and removes it when the caller stops listening.
        continuation.onTermination = { _ in
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        return stream
    }

    func frontmostApplication() async -> AppIdentity? {
        await MainActor.run { NSWorkspace.shared.frontmostApplication.flatMap(AppIdentity.init(_:)) }
    }

    /// Opens the app through Launch Services, which brings it forward if it's running and
    /// launches it if not. `NSRunningApplication.activate(options:)` reports only that the
    /// request was sent, and macOS may decline it when another app is active. A running copy is
    /// opened by its own location, so a second install of the same app isn't launched instead.
    func activate(_ app: AppIdentity) async -> Bool {
        let location = await MainActor.run {
            NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleID).first?.bundleURL
                ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleID)
        }
        guard let location else { return false }
        do {
            _ = try await NSWorkspace.shared.openApplication(
                at: location, configuration: NSWorkspace.OpenConfiguration())
            return true
        } catch {
            return false
        }
    }

    func open(_ url: URL) async -> Bool {
        await MainActor.run { NSWorkspace.shared.open(url) }
    }
}

/// Forwards workspace activations into a stream. Registered with a selector rather than a
/// block, so there's no observer token to carry into the `Sendable` termination handler.
private final class ActivationObserver: NSObject, Sendable {
    let continuation: AsyncStream<AppIdentity>.Continuation

    init(continuation: AsyncStream<AppIdentity>.Continuation) {
        self.continuation = continuation
    }

    @objc func applicationDidActivate(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
            let identity = AppIdentity(app)
        else { return }
        continuation.yield(identity)
    }
}

extension AppIdentity {
    /// Nil for processes without a bundle identifier.
    init?(_ app: NSRunningApplication) {
        guard let bundleID = app.bundleIdentifier else { return nil }
        self.init(bundleID: bundleID, name: app.localizedName)
    }
}
