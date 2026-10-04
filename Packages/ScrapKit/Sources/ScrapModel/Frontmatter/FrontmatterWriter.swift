import Foundation

/// Writes a scrap in the canonical file format. Output is deterministic: fixed key order, every
/// string double-quoted, dates in UTC to the whole second, the note as a `|` block where it can
/// be one, and unknown keys last in their order. Whatever the scrap holds, the output reads back
/// with `FrontmatterCodec.decode`.
enum FrontmatterWriter {
    static func encode(_ scrap: Scrap) -> String {
        var out = "---\n"
        func put(_ key: String, _ value: String) {
            out += key + ": " + value + "\n"
        }

        put("schema", String(ScrapSchema.current))
        put("id", quoted(scrap.id.stringValue))
        put("kind", quoted(scrap.kind.rawValue))
        put("title", quoted(scrap.title))
        put("pinned", scrap.pinned ? "true" : "false")
        put("board", quoted(scrap.board.rawValue))
        put("created", UTCTimestamp.format(scrap.created))
        put("updated", UTCTimestamp.format(scrap.updated))

        let reference = scrap.reference
        out += "reference:\n"
        put("  provider", quoted(reference.provider.rawValue))
        if let app = reference.app { put("  app", quoted(app.bundleID)) }
        if let window = reference.window { put("  window", quoted(window)) }
        switch reference.locator {
        case .app:
            break
        case .url(let url):
            put("  locator", quoted(url.absoluteString))
        case .messageID(let messageID):
            put("  locator", quoted(messageID))
        case .file(let path, let bookmark):
            put("  locator", quoted(path))
            put("  bookmark", quoted(bookmark.base64EncodedString()))
        case .screenRect(let rect):
            put("  locator", quoted("\(rect.x),\(rect.y),\(rect.width),\(rect.height)"))
        case .other(let raw):
            put("  locator", quoted(raw))
        }
        if let deepLink = reference.deepLink { put("  deepLink", quoted(deepLink.absoluteString)) }
        put("  label", quoted(reference.label))
        put("  fingerprint", quoted(reference.fingerprint.rawValue))

        if let asset = scrap.asset { put("asset", quoted(asset.path)) }
        if let note = scrap.note {
            if let block = literalBlock(note.text) {
                out += "note: " + block
            } else {
                put("note", quoted(note.text))
            }
            put("noteUpdated", UTCTimestamp.format(note.updated))
        }
        if !scrap.derivedFrom.isEmpty {
            out += "derivedFrom:\n"
            for id in scrap.derivedFrom { out += "  - " + quoted(id.stringValue) + "\n" }
        }
        if scrap.aiExcluded { put("aiExcluded", "true") }

        var writtenKeys: Set<String> = []
        for entry in scrap.extraFrontmatter {
            // Entries read from a file always pass. One built in code with a key the reader
            // would read back differently (a known key, a repeat, or one that isn't a plain YAML
            // key) is left out rather than written as a file that no longer loads.
            guard isWritableKey(entry.key), writtenKeys.insert(entry.key).inserted else { continue }
            switch entry.value {
            case .null:
                out += entry.key + ":\n"
            case .list(let items) where items.isEmpty:
                put(entry.key, "[]")
            case .list(let items):
                out += entry.key + ":\n"
                for item in items {
                    out += item == .null ? "  -\n" : "  - " + inline(item) + "\n"
                }
            default:
                put(entry.key, inline(entry.value))
            }
        }

        return out + "---\n" + scrap.body
    }

    /// A double-quoted YAML string. Quotes, backslashes, line breaks, tabs, and characters that
    /// YAML doesn't allow unescaped (or that are invisible and easily mangled) are escaped.
    static func quoted(_ text: String) -> String {
        var out = "\""
        for scalar in text.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\t": out += "\\t"
            case "\r": out += "\\r"
            default:
                if YAMLText.needsEscape(scalar) {
                    let hex = String(scalar.value, radix: 16, uppercase: true)
                    out += "\\u" + String(repeating: "0", count: max(0, 4 - hex.count)) + hex
                } else {
                    out.unicodeScalars.append(scalar)
                }
            }
        }
        return out + "\""
    }

    /// A value on one line. A `.scalar` that YAML wouldn't read as a number, boolean, null, or
    /// date is quoted, so it reads back as text instead of breaking the file. A list inside a
    /// list can't be read back as one, so it's written as its text.
    private static func inline(_ value: FrontmatterValue) -> String {
        switch value {
        case .string(let text): quoted(text)
        case .scalar(let raw): PlainScalar.isTypedLiteral(raw) ? raw : quoted(raw)
        case .null: "null"
        case .list(let items): quoted("[" + items.map(inline).joined(separator: ", ") + "]")
        }
    }

    /// An unknown key the reader would read back as itself (it accepts exactly these).
    private static func isWritableKey(_ key: String) -> Bool {
        !FrontmatterKeys.topLevel.contains(key) && YAMLText.isPlainKey(key.unicodeScalars)
    }

    /// The note as a `|` block (header line included), or nil when only a double-quoted string
    /// keeps it exact: empty or newline-only text, carriage returns, characters that need
    /// escaping, or lines holding only whitespace.
    static func literalBlock(_ text: String) -> String? {
        for scalar in text.unicodeScalars where scalar != "\n" && scalar != "\t" {
            if scalar == "\r" || YAMLText.needsEscape(scalar) { return nil }
        }
        var core = text.unicodeScalars[...]
        var trailingNewlines = 0
        while core.last == "\n" {
            core = core.dropLast()
            trailingNewlines += 1
        }
        let lines = String(core).split(separator: "\n", omittingEmptySubsequences: false)
        guard let firstContent = lines.first(where: { !$0.isEmpty }) else { return nil }
        if lines.contains(where: { !$0.isEmpty && $0.allSatisfy { $0 == " " || $0 == "\t" } }) { return nil }

        var block = "|"
        // Scalars, not Characters: a space followed by a combining mark is one Character.
        if firstContent.unicodeScalars.first == " " { block += "2" }
        switch trailingNewlines {
        case 0: block += "-"
        case 1: break
        default: block += "+"
        }
        block += "\n"
        for line in lines {
            block += line.isEmpty ? "\n" : "  " + line + "\n"
        }
        if trailingNewlines > 1 {
            block += String(repeating: "\n", count: trailingNewlines - 1)
        }
        return block
    }
}
