import Foundation
import ScrapCapture
import ScrapModel
import ScrapTestSupport
import Testing

/// The App track's tracker tests (M1-R14) and the providers' tests (M1-R12) rely on this fake
/// behaving like a workspace. A time limit makes a fake that stops yielding fail, not hang.
@Suite(.timeLimit(.minutes(1)))
struct FakeWorkspaceTests {
    @Test func everySubscriberReceivesLaterActivations() async {
        let workspace = FakeWorkspace(frontmost: AppIdentity(bundleID: "com.apple.finder"))
        let first = workspace.activations()
        let second = workspace.activations()
        workspace.simulateActivation(of: AppIdentity(bundleID: "com.apple.TextEdit"))

        var firstIterator = first.makeAsyncIterator()
        var secondIterator = second.makeAsyncIterator()
        #expect(await firstIterator.next()?.bundleID == "com.apple.TextEdit")
        #expect(await secondIterator.next()?.bundleID == "com.apple.TextEdit")
        #expect(await workspace.frontmostApplication()?.bundleID == "com.apple.TextEdit")
    }

    @Test func endedStreamUnsubscribes() async {
        let workspace = FakeWorkspace()
        let stream = workspace.activations()
        #expect(workspace.subscriberCount == 1)

        let task = Task {
            for await _ in stream {}
        }
        task.cancel()
        await task.value
        #expect(workspace.subscriberCount == 0)
    }

    @Test func activateRecordsTheAppAndMakesItFrontmost() async {
        let workspace = FakeWorkspace()
        var activations = workspace.activations().makeAsyncIterator()
        let mail = AppIdentity(bundleID: "com.apple.mail")

        #expect(await workspace.activate(mail))
        #expect(workspace.activatedApps == [mail])
        #expect(await activations.next() == mail)
        #expect(await workspace.frontmostApplication() == mail)
    }

    @Test func openRecordsTheURL() async {
        let workspace = FakeWorkspace()
        let url = URL(filePath: "/Users/me/Lease.pdf")
        #expect(await workspace.open(url))
        #expect(workspace.openedURLs == [url])
    }
}
