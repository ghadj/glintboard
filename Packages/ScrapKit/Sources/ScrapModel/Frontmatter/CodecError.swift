/// Why a scrap file couldn't be read. Line numbers count from 1 at the opening `---`.
public enum CodecError: Error, Equatable, Sendable {
    /// The file isn't valid UTF-8.
    case invalidUTF8
    /// The file doesn't start with a `---` line.
    case missingOpeningDelimiter
    /// No `---` line closes the frontmatter.
    case missingClosingDelimiter
    /// Valid YAML outside the supported subset.
    case unsupportedSyntax(line: Int, construct: UnsupportedConstruct)
    /// Not valid YAML: an unterminated quote, a bad escape, a line without `key:`, and so on.
    case invalidSyntax(line: Int)
    /// A known key whose value has the wrong type or form.
    case invalidValue(key: String, line: Int)
    /// A required key is missing.
    case missingKey(String)
    /// The same key appears twice in one map.
    case duplicateKey(String, line: Int)
    /// The file was written with a newer schema than this version reads, so it's left alone.
    case newerSchema(Int)
}

/// YAML constructs the frontmatter subset deliberately doesn't support.
public enum UnsupportedConstruct: String, Sendable, CaseIterable {
    /// `&name`
    case anchor
    /// `*name`
    case alias
    /// `!!str`, `!custom`
    case tag
    /// `{a: 1}`
    case flowMap
    /// `>`
    case foldedScalar
    /// A map inside a list or inside an unknown key, or a map nested more than one level.
    case nestedMap
    /// A list inside a list.
    case nestedList
    /// A plain or quoted value continued on the next line.
    case multilineScalar
    /// `# comment`
    case comment
    /// `%YAML 1.2`
    case directive
    /// `...`, which would end the YAML document early.
    case documentMarker
    /// `? key`, or a quoted or flow-collection key.
    case complexKey
    /// A tab used for indentation.
    case tabIndentation
}
