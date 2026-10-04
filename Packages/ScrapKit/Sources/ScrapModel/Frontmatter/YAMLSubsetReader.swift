/// One frontmatter line as Unicode scalars, without its line break (or a trailing `\r`).
/// Scalars rather than `Character`s, so a quote followed by a combining mark is still a quote.
struct YAMLLine {
    let number: Int
    let scalars: [Unicode.Scalar]

    /// Leading spaces. Tabs never count as indentation.
    var indent: Int { scalars.prefix { $0 == " " }.count }

    var isBlank: Bool { scalars.allSatisfy { $0 == " " || $0 == "\t" } }
}

enum YAMLScalar: Equatable {
    /// An unquoted value: text, or a number, boolean, null, or date by YAML's rules.
    case plain(String)
    /// A quoted or block value: always text.
    case string(String)
}

indirect enum YAMLNode {
    case scalar(YAMLScalar)
    case list([YAMLNode])
    case map([YAMLEntry])
    /// A key with no value.
    case null
}

struct YAMLEntry {
    let key: String
    let line: Int
    let node: YAMLNode
}

/// Reads the YAML subset scrap files use: a map of `key: value` lines; plain, single-quoted,
/// and double-quoted scalars; `|` literal blocks; block and flow lists of scalars; and one level
/// of nested map. Everything else throws `CodecError.unsupportedSyntax`, never guesses.
struct YAMLSubsetReader {
    private let lines: [YAMLLine]
    private var index = 0

    static func read(_ lines: [YAMLLine]) throws(CodecError) -> [YAMLEntry] {
        var reader = YAMLSubsetReader(lines: lines)
        return try reader.readMap(indent: 0, depth: 0)
    }

    private init(lines: [YAMLLine]) {
        self.lines = lines
    }

    // MARK: - Block structure

    /// Skips blank lines and returns the next line without consuming it.
    private mutating func peekContentLine() -> YAMLLine? {
        while index < lines.count, lines[index].isBlank { index += 1 }
        return index < lines.count ? lines[index] : nil
    }

    private mutating func readMap(indent: Int, depth: Int) throws(CodecError) -> [YAMLEntry] {
        var entries: [YAMLEntry] = []
        var seen: Set<String> = []
        while let line = peekContentLine() {
            try rejectTabIndentation(line)
            if line.indent < indent { break }
            if line.indent > indent { throw .unsupportedSyntax(line: line.number, construct: .multilineScalar) }
            index += 1
            let (key, valueStart) = try splitKey(line, at: indent)
            guard seen.insert(key).inserted else { throw .duplicateKey(key, line: line.number) }
            let node = try readValue(of: line, from: valueStart, keyIndent: indent, depth: depth)
            entries.append(YAMLEntry(key: key, line: line.number, node: node))
        }
        return entries
    }

    private mutating func readValue(of line: YAMLLine, from start: Int, keyIndent: Int, depth: Int)
        throws(CodecError) -> YAMLNode
    {
        let value = trimmed(line.scalars[start...])
        guard let first = value.first else {
            return try readBlock(keyIndent: keyIndent, depth: depth)
        }
        switch first {
        case "|":
            return .scalar(.string(try readLiteralBlock(header: value.dropFirst(), line: line, keyIndent: keyIndent)))
        case ">": throw .unsupportedSyntax(line: line.number, construct: .foldedScalar)
        default: return try parseInlineValue(value, line: line, inSequence: false)
        }
    }

    /// The value of a key with nothing after its colon: a list, a nested map, or null.
    private mutating func readBlock(keyIndent: Int, depth: Int) throws(CodecError) -> YAMLNode {
        guard let next = peekContentLine() else { return .null }
        let nextIndent = next.indent
        if nextIndent >= keyIndent, isSequenceItem(next, at: nextIndent) {
            return .list(try readSequence(indent: nextIndent))
        }
        if nextIndent > keyIndent {
            guard depth == 0 else { throw .unsupportedSyntax(line: next.number, construct: .nestedMap) }
            return .map(try readMap(indent: nextIndent, depth: depth + 1))
        }
        return .null
    }

    private func isSequenceItem(_ line: YAMLLine, at indent: Int) -> Bool {
        let scalars = line.scalars
        guard indent < scalars.count, scalars[indent] == "-" else { return false }
        return indent + 1 == scalars.count || scalars[indent + 1] == " " || scalars[indent + 1] == "\t"
    }

    private mutating func readSequence(indent: Int) throws(CodecError) -> [YAMLNode] {
        var items: [YAMLNode] = []
        while let line = peekContentLine(), line.indent == indent, isSequenceItem(line, at: indent) {
            try rejectTabIndentation(line)
            index += 1
            let value = trimmed(line.scalars[(indent + 1)...])
            if value.isEmpty {
                items.append(.null)
            } else {
                items.append(try parseInlineValue(value, line: line, inSequence: true))
            }
        }
        if let line = peekContentLine() {
            if line.indent > indent { throw .unsupportedSyntax(line: line.number, construct: .multilineScalar) }
            if line.indent == indent, indent > 0 { throw .invalidSyntax(line: line.number) }
        }
        return items
    }

    /// A `|` block. The header may carry a chomping indicator (`-` strip, `+` keep, none clip)
    /// and an indentation indicator (`1`–`9`), in either order.
    private mutating func readLiteralBlock(header: ArraySlice<Unicode.Scalar>, line: YAMLLine, keyIndent: Int)
        throws(CodecError) -> String
    {
        enum Chomping { case clip, strip, keep }
        var chomping = Chomping.clip
        var indicatedIndent: Int?
        var position = header.startIndex
        while position < header.endIndex {
            let scalar = header[position]
            if scalar == "-" || scalar == "+", chomping == .clip {
                chomping = scalar == "-" ? .strip : .keep
            } else if ("1"..."9").contains(scalar), indicatedIndent == nil {
                indicatedIndent = Int(scalar.value - 48)
            } else {
                break
            }
            position += 1
        }
        let rest = trimmed(header[position...])
        if let first = rest.first {
            let spaced = position < header.endIndex && (header[position] == " " || header[position] == "\t")
            if first == "#", spaced { throw .unsupportedSyntax(line: line.number, construct: .comment) }
            throw .invalidSyntax(line: line.number)
        }

        var contentIndent = indicatedIndent.map { keyIndent + $0 }
        var content: [String] = []
        while index < lines.count {
            let candidate = lines[index]
            if candidate.scalars.allSatisfy({ $0 == " " }) {
                // An empty line keeps any spaces beyond the block's indentation.
                if let blockIndent = contentIndent, candidate.scalars.count > blockIndent {
                    content.append(string(candidate.scalars[blockIndent...]))
                } else {
                    content.append("")
                }
                index += 1
                continue
            }
            let lineIndent = candidate.indent
            if contentIndent == nil {
                if lineIndent <= keyIndent { break }
                contentIndent = lineIndent
            }
            guard let blockIndent = contentIndent, lineIndent >= blockIndent else { break }
            content.append(string(candidate.scalars[blockIndent...]))
            index += 1
        }

        var trailingEmpty = 0
        while content.last?.isEmpty == true {
            content.removeLast()
            trailingEmpty += 1
        }
        guard !content.isEmpty else {
            return chomping == .keep ? String(repeating: "\n", count: trailingEmpty) : ""
        }
        let core = content.joined(separator: "\n")
        switch chomping {
        case .strip: return core
        case .clip: return core + "\n"
        case .keep: return core + "\n" + String(repeating: "\n", count: trailingEmpty)
        }
    }

    private func rejectTabIndentation(_ line: YAMLLine) throws(CodecError) {
        for scalar in line.scalars {
            if scalar == "\t" { throw .unsupportedSyntax(line: line.number, construct: .tabIndentation) }
            if scalar != " " { return }
        }
    }

    // MARK: - Keys

    /// The key at `indent`, and where its value starts.
    private func splitKey(_ line: YAMLLine, at indent: Int) throws(CodecError) -> (String, Int) {
        let scalars = line.scalars
        let first = scalars[indent]
        let next: Unicode.Scalar? = indent + 1 < scalars.count ? scalars[indent + 1] : nil
        let indicatorAlone = next == nil || next == " " || next == "\t"
        switch first {
        case "#": throw .unsupportedSyntax(line: line.number, construct: .comment)
        case "%": throw .unsupportedSyntax(line: line.number, construct: .directive)
        case "&": throw .unsupportedSyntax(line: line.number, construct: .anchor)
        case "*": throw .unsupportedSyntax(line: line.number, construct: .alias)
        case "!": throw .unsupportedSyntax(line: line.number, construct: .tag)
        case "\"", "'", "[", "{": throw .unsupportedSyntax(line: line.number, construct: .complexKey)
        case "?" where indicatorAlone: throw .unsupportedSyntax(line: line.number, construct: .complexKey)
        case "-" where indicatorAlone, "|", ">", "@", "`": throw .invalidSyntax(line: line.number)
        default: break
        }
        if Array(trimmed(scalars[indent...])) == ["." as Unicode.Scalar, ".", "."] {
            throw .unsupportedSyntax(line: line.number, construct: .documentMarker)
        }

        var colon = indent
        while colon < scalars.count {
            if scalars[colon] == ":",
                colon + 1 == scalars.count || scalars[colon + 1] == " " || scalars[colon + 1] == "\t"
            {
                break
            }
            colon += 1
        }
        guard colon < scalars.count else { throw .invalidSyntax(line: line.number) }
        let key = trimmed(scalars[indent..<colon])
        guard !key.isEmpty else { throw .invalidSyntax(line: line.number) }
        if startsComment(key) { throw .unsupportedSyntax(line: line.number, construct: .comment) }
        // Only keys the writer can write back unchanged, so an unknown key never gets lost.
        guard YAMLText.isPlainKey(key) else { throw .invalidSyntax(line: line.number) }
        return (string(key), colon + 1)
    }

    // MARK: - Inline values

    private func parseInlineValue(_ value: ArraySlice<Unicode.Scalar>, line: YAMLLine, inSequence: Bool)
        throws(CodecError) -> YAMLNode
    {
        guard let first = value.first else { return .null }
        let next: Unicode.Scalar? = value.count > 1 ? value[value.startIndex + 1] : nil
        let indicatorAlone = next == nil || next == " " || next == "\t"
        switch first {
        case "\"", "'":
            let (text, end) = try parseQuoted(value, line: line)
            try expectEnd(value[end...], line: line)
            return .scalar(.string(text))
        case "[":
            if inSequence { throw .unsupportedSyntax(line: line.number, construct: .nestedList) }
            let (items, end) = try parseFlowSequence(value, line: line)
            try expectEnd(value[end...], line: line)
            return .list(items)
        case "{": throw .unsupportedSyntax(line: line.number, construct: .flowMap)
        case "&": throw .unsupportedSyntax(line: line.number, construct: .anchor)
        case "*": throw .unsupportedSyntax(line: line.number, construct: .alias)
        case "!": throw .unsupportedSyntax(line: line.number, construct: .tag)
        case "#": throw .unsupportedSyntax(line: line.number, construct: .comment)
        case ">": throw .unsupportedSyntax(line: line.number, construct: .foldedScalar)
        case "|": throw .unsupportedSyntax(line: line.number, construct: .multilineScalar)
        case "-" where indicatorAlone:
            if inSequence { throw .unsupportedSyntax(line: line.number, construct: .nestedList) }
            throw .invalidSyntax(line: line.number)
        case "?" where indicatorAlone: throw .unsupportedSyntax(line: line.number, construct: .complexKey)
        case ":" where indicatorAlone, "@", "`", "%", ",", "]", "}": throw .invalidSyntax(line: line.number)
        default:
            if startsComment(value) { throw .unsupportedSyntax(line: line.number, construct: .comment) }
            if hasMappingIndicator(value) { throw .unsupportedSyntax(line: line.number, construct: .nestedMap) }
            return .scalar(.plain(string(value)))
        }
    }

    /// A double- or single-quoted scalar starting at `value.startIndex`, and the index after its
    /// closing quote. A quote that doesn't close on the same line is a multi-line scalar.
    private func parseQuoted(_ value: ArraySlice<Unicode.Scalar>, line: YAMLLine) throws(CodecError)
        -> (String, Int)
    {
        let quote = value[value.startIndex]
        var result = String.UnicodeScalarView()
        var position = value.startIndex + 1
        while position < value.endIndex {
            let scalar = value[position]
            if quote == "'" {
                if scalar == "'" {
                    guard position + 1 < value.endIndex, value[position + 1] == "'" else {
                        return (String(result), position + 1)
                    }
                    position += 1
                }
                result.append(scalar)
            } else if scalar == "\"" {
                return (String(result), position + 1)
            } else if scalar == "\\" {
                position += 1
                guard position < value.endIndex else {
                    throw .unsupportedSyntax(line: line.number, construct: .multilineScalar)
                }
                let (escaped, length) = try unescape(value[position...], line: line)
                result.append(escaped)
                position += length - 1
            } else {
                result.append(scalar)
            }
            position += 1
        }
        throw .unsupportedSyntax(line: line.number, construct: .multilineScalar)
    }

    /// The scalar for the escape sequence starting just after a backslash, and how many scalars
    /// the sequence used.
    private func unescape(_ value: ArraySlice<Unicode.Scalar>, line: YAMLLine) throws(CodecError)
        -> (Unicode.Scalar, Int)
    {
        let simple: [Unicode.Scalar: UInt32] = [
            "0": 0, "a": 7, "b": 8, "t": 9, "\t": 9, "n": 10, "v": 11, "f": 12, "r": 13, "e": 27, " ": 32,
            "\"": 34, "/": 47, "\\": 92, "N": 0x85, "_": 0xA0, "L": 0x2028, "P": 0x2029,
        ]
        let code = value[value.startIndex]
        if let mapped = simple[code], let scalar = Unicode.Scalar(mapped) { return (scalar, 1) }
        let digits: Int
        switch code {
        case "x": digits = 2
        case "u": digits = 4
        case "U": digits = 8
        default: throw .invalidSyntax(line: line.number)
        }
        guard value.count > digits,
            let number = UInt32(string(value.dropFirst().prefix(digits)), radix: 16),
            let scalar = Unicode.Scalar(number)
        else { throw .invalidSyntax(line: line.number) }
        return (scalar, digits + 1)
    }

    /// `[a, "b", 'c']`: a one-line list of scalars, and the index after its `]`.
    private func parseFlowSequence(_ value: ArraySlice<Unicode.Scalar>, line: YAMLLine) throws(CodecError)
        -> ([YAMLNode], Int)
    {
        var items: [YAMLNode] = []
        var position = value.startIndex + 1
        func skipSpaces() {
            while position < value.endIndex, value[position] == " " || value[position] == "\t" { position += 1 }
        }
        while true {
            skipSpaces()
            guard position < value.endIndex else {
                throw .unsupportedSyntax(line: line.number, construct: .multilineScalar)
            }
            if value[position] == "]" { return (items, position + 1) }
            switch value[position] {
            case "\"", "'":
                let (text, end) = try parseQuoted(value[position...], line: line)
                items.append(.scalar(.string(text)))
                position = end
            case "[": throw .unsupportedSyntax(line: line.number, construct: .nestedList)
            case "{": throw .unsupportedSyntax(line: line.number, construct: .flowMap)
            case "&": throw .unsupportedSyntax(line: line.number, construct: .anchor)
            case "*": throw .unsupportedSyntax(line: line.number, construct: .alias)
            case "!": throw .unsupportedSyntax(line: line.number, construct: .tag)
            case "#": throw .unsupportedSyntax(line: line.number, construct: .comment)
            case ",": throw .invalidSyntax(line: line.number)
            default:
                let start = position
                while position < value.endIndex, value[position] != ",", value[position] != "]" { position += 1 }
                let item = trimmed(value[start..<position])
                if startsComment(item) { throw .unsupportedSyntax(line: line.number, construct: .comment) }
                if hasMappingIndicator(item) { throw .unsupportedSyntax(line: line.number, construct: .flowMap) }
                if item.contains("[") || item.contains("{") || item.contains("}") {
                    throw .invalidSyntax(line: line.number)
                }
                items.append(.scalar(.plain(string(item))))
            }
            skipSpaces()
            guard position < value.endIndex else {
                throw .unsupportedSyntax(line: line.number, construct: .multilineScalar)
            }
            switch value[position] {
            case ",": position += 1
            case "]": return (items, position + 1)
            default: throw .invalidSyntax(line: line.number)
            }
        }
    }

    /// After a quoted scalar or a flow list, only spaces may follow.
    private func expectEnd(_ rest: ArraySlice<Unicode.Scalar>, line: YAMLLine) throws(CodecError) {
        let remainder = trimmed(rest)
        guard let first = remainder.first else { return }
        let spaced = rest.first == " " || rest.first == "\t"
        if first == "#", spaced { throw .unsupportedSyntax(line: line.number, construct: .comment) }
        throw .invalidSyntax(line: line.number)
    }

    // MARK: - Scalar helpers

    /// ` #` or a tab before `#` starts a comment in YAML.
    private func startsComment(_ value: ArraySlice<Unicode.Scalar>) -> Bool {
        zip(value, value.dropFirst()).contains { ($0 == " " || $0 == "\t") && $1 == "#" }
    }

    /// `: ` inside a plain scalar, or a trailing `:`, would make it a mapping.
    private func hasMappingIndicator(_ value: ArraySlice<Unicode.Scalar>) -> Bool {
        if value.last == ":" { return true }
        return zip(value, value.dropFirst()).contains { $0 == ":" && ($1 == " " || $1 == "\t") }
    }

    private func trimmed(_ value: ArraySlice<Unicode.Scalar>) -> ArraySlice<Unicode.Scalar> {
        var slice = value
        while let first = slice.first, first == " " || first == "\t" { slice = slice.dropFirst() }
        while let last = slice.last, last == " " || last == "\t" { slice = slice.dropLast() }
        return slice
    }

    private func string(_ scalars: some Sequence<Unicode.Scalar>) -> String {
        var view = String.UnicodeScalarView()
        view.append(contentsOf: scalars)
        return String(view)
    }
}

/// YAML's rules for whether a plain (unquoted) scalar is text or another type. Values of
/// unknown keys that aren't text are kept verbatim, so a number or a date stays one.
enum PlainScalar {
    static func isText(_ value: String) -> Bool {
        !isTypedLiteral(value)
    }

    /// Null, boolean, integer, and float by the YAML 1.2 core schema, plus dates and times
    /// (YAML 1.1 timestamps, also without seconds, as Obsidian writes them).
    static func isTypedLiteral(_ value: String) -> Bool {
        let keywords: Set<String> = ["null", "Null", "NULL", "~", "true", "True", "TRUE", "false", "False", "FALSE"]
        if keywords.contains(value) { return true }
        let patterns = [
            #/[-+]?[0-9]+/#,
            #/0o[0-7]+/#,
            #/0x[0-9a-fA-F]+/#,
            #/[-+]?(?:\.[0-9]+|[0-9]+(?:\.[0-9]*)?)(?:[eE][-+]?[0-9]+)?/#,
            #/[-+]?\.(?:inf|Inf|INF)/#,
            #/\.(?:nan|NaN|NAN)/#,
            #/[0-9]{4}-[0-9]{1,2}-[0-9]{1,2}/#,
            #/[0-9]{4}-[0-9]{1,2}-[0-9]{1,2}(?:[Tt]|[ \t]+)[0-9]{1,2}:[0-9]{2}(?::[0-9]{2}(?:\.[0-9]*)?)?(?:[ \t]*(?:Z|[-+][0-9]{1,2}(?::?[0-9]{2})?))?/#,
        ]
        return patterns.contains { value.wholeMatch(of: $0) != nil }
    }
}
