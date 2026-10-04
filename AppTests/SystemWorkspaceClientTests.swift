import AppKit
import ScrapModel
import Testing

@testable import App

struct SystemWorkspaceClientTests {
    @Test func activationNotificationIsStreamed() async throws {
        let client = SystemWorkspaceClient()
        var activations = client.activations().makeAsyncIterator()
        let app = NSRunningApplication.current
        let bundleID = try #require(app.bundleIdentifier)

        // Observers registered with a selector are called synchronously on post, so the
        // activation is already buffered in the stream when `next()` is awaited.
        NSWorkspace.shared.notificationCenter.post(
            name: NSWorkspace.didActivateApplicationNotification,
            object: NSWorkspace.shared,
            userInfo: [NSWorkspace.applicationUserInfoKey: app]
        )

        // A real activation (switching apps while the tests run) may arrive first; skip it. The
        // posted one is already buffered, so the loop ends.
        var received: AppIdentity?
        while let next = await activations.next() {
            if next.bundleID == bundleID {
                received = next
                break
            }
        }
        #expect(received != nil)
        #expect(received?.name == app.localizedName)
    }
}
