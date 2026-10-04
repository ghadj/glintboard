import Foundation
import ScrapModel

/// A new scrap before it has a file: what `ScrapStore.create` writes. The only way a body is
/// ever written.
public struct ScrapDraft: Sendable, Equatable {
    public var id: ScrapID
    public var kind: ScrapKind
    public var title: String
    public var body: String
    public var reference: Reference
    public var board: Rank
    /// Capture time, whole seconds; also the first `updated`.
    public var created: Date

    public init(
        id: ScrapID = ScrapID(), kind: ScrapKind, title: String, body: String, reference: Reference, board: Rank,
        created: Date
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.body = body
        self.reference = reference
        self.board = board
        self.created = created
    }
}
