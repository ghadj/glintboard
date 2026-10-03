/// A fractional board sort key, written as `board` in frontmatter. Keys compare by their bytes,
/// so a key can always be made between two others and a reorder rewrites only one file.
public struct Rank: Hashable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

extension Rank: Comparable {
    public static func < (lhs: Rank, rhs: Rank) -> Bool {
        lhs.rawValue.utf8.lexicographicallyPrecedes(rhs.rawValue.utf8)
    }
}
