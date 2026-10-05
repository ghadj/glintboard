import Foundation
import ScrapModel
import ScrapTestSupport

@testable import ScrapStorage

/// Checks on changes a `StreamRecorder` has already recorded. Don't use them as `waitFor`
/// predicates: see the note on `StreamRecorder`.
extension LibraryChange {
    /// The case's name.
    var kind: String {
        switch self {
        case .saved: "saved"
        case .updated: "updated"
        case .removed: "removed"
        case .problem: "problem"
        case .rescanNeeded: "rescanNeeded"
        }
    }

    /// An outside change at `path` that read back as the scrap with this id.
    func isUpdate(at path: String, of id: ScrapID) -> Bool {
        guard case .updated(let scrap, let file) = self else { return false }
        return file.path == path && scrap.id == id
    }

    /// An outside change at `path` whose body now ends with `suffix`.
    func isUpdate(at path: String, bodyEndingWith suffix: String) -> Bool {
        guard case .updated(let scrap, let file) = self else { return false }
        return file.path == path && scrap.body.hasSuffix(suffix)
    }
}

/// Scraps and indexes for the index tests, without a store.
enum IndexFixtures {
    static let created = Date(timeIntervalSince1970: 1_790_690_531)

    static func scrap(
        id: ScrapID = ScrapID(), title: String = "Untitled", body: String = "", note: String? = nil,
        label: String = "TextEdit", window: String? = nil, board: Rank = Rank.after(nil),
        updated: Date = created
    ) -> Scrap {
        Scrap(
            id: id, kind: .text, title: title, body: body, board: board, created: created, updated: updated,
            reference: Reference(
                provider: .fallback, app: AppIdentity(bundleID: "com.apple.TextEdit"), window: window, locator: .app,
                label: label, fingerprint: Fingerprint.text(body)),
            note: note.map { Note(text: $0, updated: created) })
    }

    static func saved(_ scrap: Scrap, at path: String? = nil, collection: String = "Inbox") -> LibraryChange {
        let path = path ?? "\(collection)/\(scrap.id.shortHex)-\(scrap.id.stringValue).md"
        return .saved(scrap, file: ScrapFileInfo(path: path, modified: created, size: scrap.body.utf8.count))
    }

    /// A freshly opened index in a temporary folder.
    static func openIndex(engine: FullTextEngine? = nil) async throws -> (TemporaryLibrary, ScrapIndex) {
        let library = try TemporaryLibrary()
        let index = ScrapIndex(databaseURL: library.base.appending(path: ".index.sqlite"), engine: engine)
        try await index.open()
        return (library, index)
    }
}
