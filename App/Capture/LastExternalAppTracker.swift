import ScrapCapture
import ScrapModel

/// Remembers the most recent frontmost app other than this one, so a capture can name the app
/// it came from even after the shelf has taken the keyboard (architecture rule 9).
///
/// Event-driven only: it's seeded once from the frontmost app and then follows the
/// workspace's activations. Nothing polls.
@MainActor
final class LastExternalAppTracker {
    /// The last external app to become frontmost, or nil before any is known.
    private(set) var current: AppIdentity?

    private let workspace: any WorkspaceClient
    private let ownBundleID: String
    private var started = false
    private var following: Task<Void, Never>?

    init(workspace: any WorkspaceClient, ownBundleID: String) {
        self.workspace = workspace
        self.ownBundleID = ownBundleID
    }

    /// Seeds `current` from the frontmost app, then follows activations until the tracker is
    /// released, which ends its subscription. Returns once seeded. Calling it again does nothing.
    func start() async {
        guard !started else { return }
        started = true
        // Subscribe before asking for the frontmost app, so an activation that happens while
        // the seed is in flight is buffered and applied after it, not lost.
        let activations = workspace.activations()
        if let frontmost = await workspace.frontmostApplication() {
            record(frontmost)
        }
        following = Task { [weak self] in
            for await app in activations {
                guard let self else { return }
                record(app)
            }
        }
    }

    deinit {
        following?.cancel()
    }

    /// Takes `app` as the latest frontmost app, unless it's this app.
    func record(_ app: AppIdentity) {
        guard app.bundleID != ownBundleID else { return }
        current = app
    }
}
