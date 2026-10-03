import Foundation

/// A collection: a folder under the library root. Its name is the folder name; display order
/// and creation date live in the folder's `.collection.json`.
public struct CollectionInfo: Sendable, Equatable {
    public var name: String
    public var order: Int
    public var created: Date

    public init(name: String, order: Int, created: Date) {
        self.name = name
        self.order = order
        self.created = created
    }
}
