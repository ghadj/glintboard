import Foundation

/// What a scrap holds; drives rendering and paste behavior.
public enum ScrapKind: String, Sendable, CaseIterable {
    case text, link, image, file
}

/// One captured item: content plus exactly one reference, stored as a Markdown file.
///
/// The collection isn't a field: it's the folder the file is in. Reference health lives in
/// the index, never here.
public struct Scrap: Sendable, Equatable {
    public var id: ScrapID
    /// Frontmatter schema version of the file this came from, or the current one for new scraps.
    public var schema: Int
    public var kind: ScrapKind
    public var title: String
    /// The Markdown body: the captured text, or the URL for links; empty for images and files.
    /// Captured text is immutable: only capture writes it.
    public var body: String
    /// The stored image, or a file scrap's thumbnail.
    public var asset: AssetRef?
    public var pinned: Bool
    /// Board sort key.
    public var board: Rank
    public var created: Date
    /// Last capture or edit; a duplicate capture bumps it.
    public var updated: Date
    public var reference: Reference
    public var note: Note?
    /// Scraps this one was built from (AI summaries, merges). Reserved in schema 1.
    public var derivedFrom: [ScrapID]
    /// Keeps the scrap out of every AI feature. Reserved in schema 1.
    public var aiExcluded: Bool
    /// Frontmatter keys this version doesn't know (for example tags added in Obsidian), in
    /// file order, so they survive a rewrite.
    public var extraFrontmatter: [FrontmatterEntry]

    public init(
        id: ScrapID,
        schema: Int = ScrapSchema.current,
        kind: ScrapKind,
        title: String,
        body: String,
        asset: AssetRef? = nil,
        pinned: Bool = false,
        board: Rank,
        created: Date,
        updated: Date,
        reference: Reference,
        note: Note? = nil,
        derivedFrom: [ScrapID] = [],
        aiExcluded: Bool = false,
        extraFrontmatter: [FrontmatterEntry] = []
    ) {
        self.id = id
        self.schema = schema
        self.kind = kind
        self.title = title
        self.body = body
        self.asset = asset
        self.pinned = pinned
        self.board = board
        self.created = created
        self.updated = updated
        self.reference = reference
        self.note = note
        self.derivedFrom = derivedFrom
        self.aiExcluded = aiExcluded
        self.extraFrontmatter = extraFrontmatter
    }
}

/// The user's own annotation, kept apart from the captured content (`note` and `noteUpdated`).
public struct Note: Sendable, Equatable {
    public var text: String
    public var updated: Date

    public init(text: String, updated: Date) {
        self.text = text
        self.updated = updated
    }
}

/// A file in the collection's `assets/` folder: a stored image or a file scrap's thumbnail.
public struct AssetRef: Hashable, Sendable {
    /// Relative to the collection folder, for example `assets/c71e-floorplan.png`.
    public var path: String

    public init(path: String) {
        self.path = path
    }
}
