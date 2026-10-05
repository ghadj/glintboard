import Foundation

/// What the user typed in the search field, made safe for an FTS `MATCH`.
public struct SearchQuery: Sendable, Equatable {
    public var text: String
    /// Limits results to one collection; nil searches all.
    public var collection: CollectionName?

    public init(_ text: String, in collection: CollectionName? = nil) {
        self.text = text
        self.collection = collection
    }

    /// Words with at least one letter or digit, each quoted so that `*`, `AND`, `OR`, `NOT`,
    /// and `NEAR` are taken literally. Words are split at quotes too: FTS4 has no way to escape
    /// a quote inside a phrase, and the tokenizer treats a quote as a separator anyway, so both
    /// engines see the same words. The last word matches as a prefix, so results follow typing.
    /// Nil if there's nothing to search for.
    func matchExpression(for engine: FullTextEngine) -> String? {
        let words = text.split { $0.isWhitespace || $0 == "\"" }
            .filter { $0.unicodeScalars.contains { $0.properties.isAlphabetic || $0.properties.numericType != nil } }
        guard !words.isEmpty else { return nil }
        return words.enumerated().map { offset, word in
            guard offset == words.count - 1 else { return "\"\(word)\"" }
            // FTS5 puts the prefix star after the quoted phrase; FTS4 inside it.
            switch engine {
            case .fts5: return "\"\(word)\"*"
            case .fts4: return "\"\(word)*\""
            }
        }.joined(separator: " ")
    }
}
