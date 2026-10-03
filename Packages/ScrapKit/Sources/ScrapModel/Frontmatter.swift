import Foundation

/// One top-level frontmatter key and its value, used for keys this version doesn't know.
public struct FrontmatterEntry: Sendable, Equatable {
    public var key: String
    public var value: FrontmatterValue

    public init(key: String, value: FrontmatterValue) {
        self.key = key
        self.value = value
    }
}

/// A frontmatter value within the supported YAML subset.
public enum FrontmatterValue: Sendable, Equatable {
    case string(String)
    case integer(Int)
    case bool(Bool)
    case date(Date)
    case list([FrontmatterValue])
}
