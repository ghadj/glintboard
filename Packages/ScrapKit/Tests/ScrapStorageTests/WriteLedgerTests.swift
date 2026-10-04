import Foundation
import Testing

@testable import ScrapStorage

struct WriteLedgerTests {
    private let start = Date(timeIntervalSince1970: 1_790_690_531)

    @Test func matchingHashWithinWindowIsEcho() {
        var ledger = WriteLedger()
        ledger.record(path: "Inbox/a.md", hash: "sha256:aa", at: start)
        #expect(ledger.isEcho(path: "Inbox/a.md", hash: "sha256:aa", now: start.addingTimeInterval(4.9)))
        // Several FSEvents for one write: each is still an echo.
        #expect(ledger.isEcho(path: "Inbox/a.md", hash: "sha256:aa", now: start.addingTimeInterval(4.9)))
    }

    @Test func differentHashIsNotEcho() {
        var ledger = WriteLedger()
        ledger.record(path: "Inbox/a.md", hash: "sha256:aa", at: start)
        #expect(!ledger.isEcho(path: "Inbox/a.md", hash: "sha256:bb", now: start))
        #expect(!ledger.isEcho(path: "Inbox/b.md", hash: "sha256:aa", now: start))
    }

    @Test func entryExpiresAfterFiveSeconds() {
        var ledger = WriteLedger()
        ledger.record(path: "Inbox/a.md", hash: "sha256:aa", at: start)
        #expect(!ledger.isEcho(path: "Inbox/a.md", hash: "sha256:aa", now: start.addingTimeInterval(5)))
    }

    /// Two writes in a row: the file now holds the second, so that's the echo to expect.
    @Test func laterWriteToSamePathReplacesTheEntry() {
        var ledger = WriteLedger()
        ledger.record(path: "Inbox/a.md", hash: "sha256:aa", at: start)
        ledger.record(path: "Inbox/a.md", hash: "sha256:bb", at: start.addingTimeInterval(1))
        #expect(ledger.isEcho(path: "Inbox/a.md", hash: "sha256:bb", now: start.addingTimeInterval(2)))
        #expect(!ledger.isEcho(path: "Inbox/a.md", hash: "sha256:aa", now: start.addingTimeInterval(2)))
    }

    @Test func oldEntriesArePruned() {
        var ledger = WriteLedger()
        for index in 0..<100 {
            ledger.record(path: "Inbox/\(index).md", hash: "sha256:aa", at: start)
        }
        ledger.record(path: "Inbox/new.md", hash: "sha256:bb", at: start.addingTimeInterval(10))
        #expect(ledger.count == 1)
    }
}
