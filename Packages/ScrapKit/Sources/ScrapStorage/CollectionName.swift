/// A collection's name, which is its folder's name under the library root.
public struct CollectionName: Hashable, Sendable {
    public let rawValue: String

    /// Nil for names that can't be a collection folder: empty or blank, starting with a dot
    /// (dot-folders hold the app's own data), or containing `/`, `:`, or control characters.
    public init?(_ rawValue: String) {
        guard !rawValue.isEmpty, !rawValue.hasPrefix("."),
            !rawValue.allSatisfy(\.isWhitespace),
            !rawValue.unicodeScalars.contains(where: {
                $0 == "/" || $0 == ":" || $0.properties.generalCategory == .control
            })
        else { return nil }
        self.rawValue = rawValue
    }

    private init(unchecked rawValue: String) {
        self.rawValue = rawValue
    }

    /// The default collection. The folder is always named "Inbox"; only the name shown in the
    /// app is localized.
    public static let inbox = CollectionName(unchecked: "Inbox")
}
