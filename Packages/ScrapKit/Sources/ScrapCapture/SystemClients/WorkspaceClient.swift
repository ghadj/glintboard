import Foundation
import ScrapModel

/// The parts of `NSWorkspace` the capture side needs: which app is frontmost, when that
/// changes, and opening apps and files. The app implements it; tests use `FakeWorkspace`.
public protocol WorkspaceClient: Sendable {
    /// App activations as they happen, from the moment of the call. Each call returns its own
    /// stream; it ends when the caller stops iterating.
    func activations() -> AsyncStream<AppIdentity>

    /// The app that is frontmost right now, if any.
    func frontmostApplication() async -> AppIdentity?

    /// Brings an app to the front, launching it if needed. False if it couldn't be found.
    func activate(_ app: AppIdentity) async -> Bool

    /// Opens a URL (such as a `file://` URL) in its default app. False if nothing opened it.
    func open(_ url: URL) async -> Bool
}
