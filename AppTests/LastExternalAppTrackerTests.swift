import ScrapModel
import ScrapTestSupport
import Testing

@testable import App

@MainActor
struct LastExternalAppTrackerTests {
    private let own = AppIdentity(bundleID: "com.example.shelf")
    private let textEdit = AppIdentity(bundleID: "com.apple.TextEdit")
    private let safari = AppIdentity(bundleID: "com.apple.Safari")
    private let finder = AppIdentity(bundleID: "com.apple.finder")

    @Test func startsWithFrontmostApp() async {
        let workspace = FakeWorkspace(frontmost: textEdit)
        let tracker = LastExternalAppTracker(workspace: workspace, ownBundleID: own.bundleID)
        #expect(tracker.current == nil)

        await tracker.start()

        #expect(tracker.current == textEdit)
    }

    @Test func remembersMostRecentExternalApp() async {
        let workspace = FakeWorkspace(frontmost: textEdit)
        let tracker = LastExternalAppTracker(workspace: workspace, ownBundleID: own.bundleID)
        await tracker.start()
        #expect(workspace.subscriberCount == 1)

        workspace.simulateActivation(of: safari)
        workspace.simulateActivation(of: finder)

        #expect(await eventually { tracker.current == finder })
    }

    @Test func ignoresOwnActivations() async {
        let workspace = FakeWorkspace(frontmost: own)
        let tracker = LastExternalAppTracker(workspace: workspace, ownBundleID: own.bundleID)
        await tracker.start()
        #expect(tracker.current == nil)

        tracker.record(textEdit)
        tracker.record(own)

        #expect(tracker.current == textEdit)
    }
}
