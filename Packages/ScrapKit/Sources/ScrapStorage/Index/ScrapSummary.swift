import Foundation
import ScrapModel

/// What a card needs, read from the index rather than the scrap's file.
public struct ScrapSummary: Sendable, Equatable, Identifiable {
    public let id: ScrapID
    public let collection: String
    /// The file, relative to the library root.
    public let path: String
    public let kind: ScrapKind
    public let title: String
    /// The start of the body (up to 300 characters), for the card's two lines.
    public let preview: String
    public let label: String
    public let provider: ProviderID
    public let pinned: Bool
    public let board: Rank?
    public let created: Date
    public let updated: Date
    /// The stored image or file thumbnail, relative to the collection folder.
    public let asset: String?
    public let hasNote: Bool
}
