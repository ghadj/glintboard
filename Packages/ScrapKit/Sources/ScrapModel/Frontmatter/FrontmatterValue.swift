/// One top-level frontmatter key and its value, used for keys this version doesn't know.
public struct FrontmatterEntry: Sendable, Equatable {
    public var key: String
    public var value: FrontmatterValue

    public init(key: String, value: FrontmatterValue) {
        self.key = key
        self.value = value
    }
}

/// The value of a frontmatter key this version doesn't know (for example Obsidian's `tags`),
/// kept so it survives a rewrite with its type intact.
public enum FrontmatterValue: Sendable, Equatable {
    /// Text. Written double-quoted.
    case string(String)
    /// A plain value that YAML reads as something other than text: a number (`4.5`), a boolean
    /// (`true`), a null (`null`, `~`), or a date (`2026-10-15`, `2026-10-15T14:30`). Kept and
    /// written exactly as it appeared, unquoted, so other tools still see a number or a date.
    case scalar(String)
    /// A key with no value (`key:`).
    case null
    /// A list of values; items are never lists themselves.
    case list([FrontmatterValue])
}
