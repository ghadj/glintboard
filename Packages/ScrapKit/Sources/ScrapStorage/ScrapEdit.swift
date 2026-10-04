import ScrapModel

/// Every change the store can make to an existing scrap. There's deliberately no case for the
/// body or the kind: captured text is immutable, and corrections go in the note.
public enum ScrapEdit: Sendable, Equatable {
    case title(String)
    /// Sets the note (and `noteUpdated`), or removes it with nil.
    case note(String?)
    case pinned(Bool)
    case board(Rank)
    /// The provider's reference replacing the fallback (capture enrichment), not a user edit.
    case reference(Reference)
    /// The stored image or a file's thumbnail, once generated.
    case asset(AssetRef?)

    /// The kinds of edit, so tests can cover each one and notice a new one.
    public enum Kind: String, Sendable, CaseIterable {
        case title, note, pinned, board, reference, asset
    }

    public var kind: Kind {
        switch self {
        case .title: .title
        case .note: .note
        case .pinned: .pinned
        case .board: .board
        case .reference: .reference
        case .asset: .asset
        }
    }
}
