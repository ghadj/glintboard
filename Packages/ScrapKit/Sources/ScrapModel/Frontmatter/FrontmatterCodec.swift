import Foundation

/// Reads and writes scrap files: YAML-subset frontmatter between `---` lines, then the body.
///
/// Reading is strict: anything outside the subset is a typed error and the file is left alone.
/// Writing always produces the canonical form, so a file written by another tool changes at most
/// once, the first time this app saves it. The body is kept byte for byte.
public enum FrontmatterCodec {
    public static func decode(_ data: Data) throws(CodecError) -> Scrap {
        guard let text = String(validating: data, as: UTF8.self) else { throw .invalidUTF8 }
        return try decode(text)
    }

    public static func decode(_ text: String) throws(CodecError) -> Scrap {
        let (lines, body) = try split(text)
        // A newer version's file may use syntax this one can't read, so its schema is checked
        // before the rest: the error then says the file needs a newer app.
        if let schema = declaredSchema(in: lines), schema > ScrapSchema.current { throw .newerSchema(schema) }
        let entries = try YAMLSubsetReader.read(lines)
        return try ScrapFields(entries).scrap(body: body)
    }

    public static func encode(_ scrap: Scrap) -> String {
        FrontmatterWriter.encode(scrap)
    }

    /// The frontmatter lines (numbered from 2, after the opening `---`) and the body after the
    /// closing `---` line. Works on Unicode scalars, so a `\r\n` pair splits cleanly. A leading
    /// byte-order mark, which some editors add, is skipped (and not written back).
    private static func split(_ text: String) throws(CodecError) -> ([YAMLLine], String) {
        let scalars = text.unicodeScalars
        var lines: [YAMLLine] = []
        var start = scalars.first == "\u{FEFF}" ? scalars.index(after: scalars.startIndex) : scalars.startIndex
        var number = 1
        while true {
            let newline = scalars[start...].firstIndex(of: "\n")
            var content = Array(scalars[start..<(newline ?? scalars.endIndex)])
            if content.last == "\r" { content.removeLast() }
            let isDelimiter = content == ["-", "-", "-"]
            if number == 1 {
                guard isDelimiter, newline != nil else { throw .missingOpeningDelimiter }
            } else if isDelimiter {
                let body = newline.map { String(scalars[scalars.index(after: $0)...]) } ?? ""
                return (lines, body)
            } else {
                lines.append(YAMLLine(number: number, scalars: content))
            }
            guard let newline else { throw .missingClosingDelimiter }
            start = scalars.index(after: newline)
            number += 1
        }
    }

    /// The integer on a top-level `schema:` line, read without parsing the rest.
    private static func declaredSchema(in lines: [YAMLLine]) -> Int? {
        for line in lines {
            var view = String.UnicodeScalarView()
            view.append(contentsOf: line.scalars)
            let text = String(view)
            guard text.hasPrefix("schema:") else { continue }
            return Int(text.dropFirst("schema:".count).trimmingCharacters(in: .whitespaces))
        }
        return nil
    }
}

/// The keys this version reads; any others are kept as unknown keys.
enum FrontmatterKeys {
    static let topLevel: Set<String> = [
        "schema", "id", "kind", "title", "pinned", "board", "created", "updated", "reference", "asset", "note",
        "noteUpdated", "derivedFrom", "aiExcluded",
    ]
    static let reference: Set<String> = [
        "provider", "app", "window", "locator", "bookmark", "deepLink", "label", "fingerprint",
    ]
}

/// Maps parsed frontmatter entries to a `Scrap`.
private struct ScrapFields {
    private var known: [String: YAMLEntry] = [:]
    private var unknown: [YAMLEntry] = []

    init(_ entries: [YAMLEntry]) {
        for entry in entries {
            if FrontmatterKeys.topLevel.contains(entry.key) {
                // A known key with no value (`title:`, as an editor may leave an emptied
                // property) counts as absent: optional keys take their defaults.
                if case .null = entry.node { continue }
                known[entry.key] = entry
            } else {
                unknown.append(entry)
            }
        }
    }

    func scrap(body: String) throws(CodecError) -> Scrap {
        // The schema comes first: a newer file is left alone whatever else it contains.
        let schemaEntry = try required("schema")
        let schema = try integer(schemaEntry)
        if schema > ScrapSchema.current { throw .newerSchema(schema) }
        if schema < 1 { throw .invalidValue(key: "schema", line: schemaEntry.line) }

        let idEntry = try required("id")
        guard let id = ScrapID(string: try text(idEntry)) else { throw invalid(idEntry) }
        let kindEntry = try required("kind")
        guard let kind = ScrapKind(rawValue: try text(kindEntry)) else { throw invalid(kindEntry) }
        let boardEntry = try required("board")
        guard let board = Rank(rawValue: try text(boardEntry)) else { throw invalid(boardEntry) }
        let created = try date(try required("created"))
        let updated = try date(try required("updated"))
        let reference = try self.reference(try required("reference"))

        var note: Note?
        if let noteEntry = known["note"], let noteText = try optionalText(noteEntry) {
            // A note added by hand without its date takes the scrap's.
            let noteUpdated = try known["noteUpdated"].map { (entry) throws(CodecError) in try date(entry) }
            note = Note(text: noteText, updated: noteUpdated ?? updated)
        }

        var derivedFrom: [ScrapID] = []
        if let entry = known["derivedFrom"] {
            switch entry.node {
            case .null:
                break
            case .list(let items):
                for item in items {
                    guard case .scalar(let scalar) = item, let id = ScrapID(string: scalarText(scalar)) else {
                        throw invalid(entry)
                    }
                    derivedFrom.append(id)
                }
            default:
                throw invalid(entry)
            }
        }

        var extra: [FrontmatterEntry] = []
        for entry in unknown {
            extra.append(FrontmatterEntry(key: entry.key, value: try value(of: entry.node, line: entry.line)))
        }

        return Scrap(
            id: id,
            schema: schema,
            kind: kind,
            title: try known["title"].map { (entry) throws(CodecError) in try text(entry) } ?? "",
            body: body,
            asset: try known["asset"].flatMap { (entry) throws(CodecError) in try optionalText(entry) }.map(
                AssetRef.init),
            pinned: try known["pinned"].map { (entry) throws(CodecError) in try bool(entry) } ?? false,
            board: board,
            created: created,
            updated: updated,
            reference: reference,
            note: note,
            derivedFrom: derivedFrom,
            aiExcluded: try known["aiExcluded"].map { (entry) throws(CodecError) in try bool(entry) } ?? false,
            extraFrontmatter: extra
        )
    }

    // MARK: - Reference

    private func reference(_ entry: YAMLEntry) throws(CodecError) -> Reference {
        guard case .map(let entries) = entry.node else { throw invalid(entry) }
        var fields: [String: YAMLEntry] = [:]
        for field in entries {
            // Unknown keys inside `reference` can't be kept (only top-level ones are), so the
            // file is rejected rather than rewritten without them.
            guard FrontmatterKeys.reference.contains(field.key) else {
                throw .invalidValue(key: "reference." + field.key, line: field.line)
            }
            if case .null = field.node { continue }
            fields[field.key] = field
        }
        func requiredField(_ key: String) throws(CodecError) -> YAMLEntry {
            guard let field = fields[key] else { throw .missingKey("reference." + key) }
            return field
        }
        func optionalField(_ key: String) throws(CodecError) -> String? {
            guard let field = fields[key] else { return nil }
            return try optionalText(field, name: "reference." + key)
        }

        let provider = ProviderID(rawValue: try text(try requiredField("provider"), name: "reference.provider"))
        let label = try text(try requiredField("label"), name: "reference.label")
        let fingerprint = Fingerprint(
            rawValue: try text(try requiredField("fingerprint"), name: "reference.fingerprint"))
        let app = try optionalField("app").map { AppIdentity(bundleID: $0) }
        let window = try optionalField("window")

        var deepLink: URL?
        if let field = fields["deepLink"], let raw = try optionalText(field, name: "reference.deepLink") {
            guard let url = URL(string: raw, encodingInvalidCharacters: false) else {
                throw .invalidValue(key: "reference.deepLink", line: field.line)
            }
            deepLink = url
        }

        let locator: Locator
        let rawLocator = try optionalField("locator")
        let rawBookmark = try optionalField("bookmark")
        switch (rawLocator, rawBookmark) {
        case (nil, nil):
            locator = .app
        case (let path?, let encoded?):
            guard let bookmark = Data(base64Encoded: encoded) else {
                throw .invalidValue(key: "reference.bookmark", line: fields["bookmark"]?.line ?? entry.line)
            }
            locator = .file(path: path, bookmark: bookmark)
        case (nil, _?):
            throw .invalidValue(key: "reference.bookmark", line: fields["bookmark"]?.line ?? entry.line)
        case (let raw?, nil):
            locator = Self.locator(raw, provider: provider)
        }

        return Reference(
            provider: provider, app: app, window: window, locator: locator, deepLink: deepLink, label: label,
            fingerprint: fingerprint)
    }

    /// How each provider writes its locator (file locators are recognized earlier, by their
    /// bookmark): Mail a Message-ID, screenshots a rectangle, Safari an absolute URL. Anything
    /// else, including a locator from a provider this version doesn't know, is kept as written.
    private static func locator(_ raw: String, provider: ProviderID) -> Locator {
        switch provider {
        case .mail:
            return .messageID(raw)
        case .screenshot:
            return screenRect(raw).map(Locator.screenRect) ?? .other(raw)
        case .safari:
            guard let url = URL(string: raw, encodingInvalidCharacters: false), url.scheme != nil else {
                return .other(raw)
            }
            return .url(url)
        default:
            return .other(raw)
        }
    }

    private static func screenRect(_ raw: String) -> ScreenRect? {
        let numbers = raw.split(separator: ",", omittingEmptySubsequences: false).compactMap { Double($0) }
        guard numbers.count == 4, numbers.allSatisfy(\.isFinite) else { return nil }
        return ScreenRect(x: numbers[0], y: numbers[1], width: numbers[2], height: numbers[3])
    }

    // MARK: - Values

    private func required(_ key: String) throws(CodecError) -> YAMLEntry {
        guard let entry = known[key] else { throw .missingKey(key) }
        return entry
    }

    private func invalid(_ entry: YAMLEntry, name: String? = nil) -> CodecError {
        .invalidValue(key: name ?? entry.key, line: entry.line)
    }

    private func scalarText(_ scalar: YAMLScalar) -> String {
        switch scalar {
        case .plain(let text), .string(let text): text
        }
    }

    private func text(_ entry: YAMLEntry, name: String? = nil) throws(CodecError) -> String {
        guard case .scalar(let scalar) = entry.node else { throw invalid(entry, name: name) }
        return scalarText(scalar)
    }

    /// Text, or nil for a key with no value or a plain YAML null (`null`, `~`).
    private func optionalText(_ entry: YAMLEntry, name: String? = nil) throws(CodecError) -> String? {
        switch entry.node {
        case .null: return nil
        case .scalar(.plain(let raw)) where ["null", "Null", "NULL", "~"].contains(raw): return nil
        default: return try text(entry, name: name)
        }
    }

    private func integer(_ entry: YAMLEntry) throws(CodecError) -> Int {
        guard case .scalar(.plain(let raw)) = entry.node, let value = Int(raw) else { throw invalid(entry) }
        return value
    }

    private func bool(_ entry: YAMLEntry) throws(CodecError) -> Bool {
        guard case .scalar(.plain(let raw)) = entry.node else { throw invalid(entry) }
        switch raw {
        case "true": return true
        case "false": return false
        default: throw invalid(entry)
        }
    }

    private func date(_ entry: YAMLEntry) throws(CodecError) -> Date {
        guard let date = UTCTimestamp.parse(try text(entry)) else { throw invalid(entry) }
        return date
    }

    /// An unknown key's value, typed as YAML would read it.
    private func value(of node: YAMLNode, line: Int) throws(CodecError) -> FrontmatterValue {
        switch node {
        case .null:
            return .null
        case .scalar(.string(let text)):
            return .string(text)
        case .scalar(.plain(let raw)):
            return PlainScalar.isText(raw) ? .string(raw) : .scalar(raw)
        case .list(let items):
            var values: [FrontmatterValue] = []
            for item in items { values.append(try value(of: item, line: line)) }
            return .list(values)
        case .map:
            throw .unsupportedSyntax(line: line, construct: .nestedMap)
        }
    }
}
