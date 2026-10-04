import Foundation
import ScrapModel
import ScrapTestSupport
import Testing

struct FrontmatterCodecTests {
    // MARK: - The design doc's example

    @Test func decodesDesignDocExample() throws {
        let scrap = try FrontmatterCodec.decode(try Fixtures.text("design-example.md"))
        #expect(scrap.schema == 1)
        #expect(scrap.id.stringValue == "8f3a0c2d-5d0f-4c8e-9a51-3c1e7a2b71e4")
        #expect(scrap.kind == .text)
        #expect(scrap.title == "2BR on Elm St")
        #expect(scrap.pinned == false)
        #expect(scrap.board.rawValue == "a3")
        #expect(scrap.created == Date(timeIntervalSince1970: 1_790_690_531))
        #expect(scrap.reference.provider == .safari)
        #expect(scrap.reference.app?.bundleID == "com.apple.Safari")
        #expect(scrap.reference.window == "2BR Apartment - Zillow")
        #expect(scrap.reference.locator == .url(URL(string: "https://www.zillow.com/homedetails/4471")!))
        #expect(
            scrap.reference.deepLink?.absoluteString
                == "https://www.zillow.com/homedetails/4471#:~:text=2BR,laundry")
        #expect(scrap.reference.label == "zillow.com")
        #expect(scrap.reference.fingerprint.rawValue == "sha256:9b2f...")
        #expect(scrap.note?.text == "Close to work, but ask about parking.\n")
        #expect(scrap.note?.updated == Date(timeIntervalSince1970: 1_790_690_740))
        #expect(scrap.body == "2BR, 850 sq ft, $2,400/mo, in-unit laundry\n")
        #expect(scrap.derivedFrom.isEmpty && !scrap.aiExcluded && scrap.extraFrontmatter.isEmpty)
    }

    /// The writer's output for the design doc's example is the example itself, byte for byte:
    /// key order, quoting, plain identifiers, dates, and the note block all match the spec.
    @Test func designDocExampleIsWrittenExactly() throws {
        let text = try Fixtures.text("design-example.md")
        #expect(FrontmatterCodec.encode(try FrontmatterCodec.decode(text)) == text)
    }

    // MARK: - Writing

    @Test func writerDoubleQuotesEveryString() throws {
        var scrap = Self.sample()
        scrap.title = "true"
        scrap.reference.window = "123"
        scrap.reference.label = "null"
        let text = FrontmatterCodec.encode(scrap)
        #expect(text.contains("\ntitle: \"true\"\n"))
        #expect(text.contains("\n  window: \"123\"\n"))
        #expect(text.contains("\n  label: \"null\"\n"))
        #expect(text.contains("\nboard: \"a3\"\n"))
        #expect(text.contains("\n  app: \"com.apple.TextEdit\"\n"))
        #expect(text.contains("\nkind: \"text\"\n"))
        #expect(text.contains("\n  provider: \"fallback\"\n"))
    }

    /// Values built in code that the reader couldn't read back as written are written so the
    /// file still loads: a non-literal `.scalar` is quoted, a nested list becomes its text, and
    /// entries whose key isn't a plain unknown key are left out.
    @Test func writerOutputAlwaysReadsBack() throws {
        var scrap = Self.sample()
        scrap.extraFrontmatter = [
            FrontmatterEntry(key: "loose", value: .scalar("not: a literal # really")),
            FrontmatterEntry(key: "nested", value: .list([.list([.string("a")])])),
            FrontmatterEntry(key: "title", value: .string("shadows a known key")),
            FrontmatterEntry(key: "a: b", value: .null),
            FrontmatterEntry(key: "line\nbreak", value: .null),
            FrontmatterEntry(key: "loose", value: .string("repeat")),
        ]
        let decoded = try FrontmatterCodec.decode(FrontmatterCodec.encode(scrap))
        #expect(decoded.title == scrap.title)
        #expect(
            decoded.extraFrontmatter == [
                FrontmatterEntry(key: "loose", value: .string("not: a literal # really")),
                FrontmatterEntry(key: "nested", value: .list([.string("[\"a\"]")])),
            ])
    }

    @Test func writerUsesFixedKeyOrder() throws {
        var scrap = Self.sample()
        scrap.asset = AssetRef(path: "assets/8f3a-plan.png")
        scrap.note = Note(text: "n", updated: scrap.created)
        scrap.derivedFrom = [scrap.id]
        scrap.aiExcluded = true
        scrap.reference.window = "w"
        scrap.reference.deepLink = URL(string: "file:///tmp/a.pdf")
        scrap.reference.locator = .file(path: "/tmp/a.pdf", bookmark: Data([1, 2, 3]))
        scrap.extraFrontmatter = [
            FrontmatterEntry(key: "zebra", value: .null), FrontmatterEntry(key: "alpha", value: .null),
        ]
        let keys = FrontmatterCodec.encode(scrap).split(separator: "\n").compactMap { line -> String? in
            guard !line.hasPrefix("    "), !line.hasPrefix("  -"), let colon = line.firstIndex(of: ":") else {
                return nil
            }
            return line[..<colon].trimmingCharacters(in: .whitespaces)
        }
        #expect(
            keys == [
                "schema", "id", "kind", "title", "pinned", "board", "created", "updated", "reference",
                "provider", "app", "window", "locator", "bookmark", "deepLink", "label", "fingerprint",
                "asset", "note", "noteUpdated", "derivedFrom", "aiExcluded", "zebra", "alpha",
            ])
    }

    @Test func escapesQuotesBackslashesAndControlCharacters() throws {
        var scrap = Self.sample()
        scrap.title = "say \"hi\" \\ tab\there\nnext\r\u{7}\u{85}\u{2028}\u{FEFF}é🏠"
        let text = FrontmatterCodec.encode(scrap)
        #expect(text.contains(#"title: "say \"hi\" \\ tab\there\nnext\r\u0007\u0085\u2028\uFEFFé🏠""#))
        #expect(try FrontmatterCodec.decode(text).title == scrap.title)
    }

    @Test func datesAreWrittenAsUTCWholeSeconds() throws {
        var scrap = Self.sample()
        scrap.created = Date(timeIntervalSince1970: 1_790_690_531.75)
        let text = FrontmatterCodec.encode(scrap)
        #expect(text.contains("\ncreated: 2026-09-29T14:02:11Z\n"))
    }

    @Test(arguments: [
        ("Close to work.", "note: |-\n  Close to work.\n"),
        ("Close to work.\n", "note: |\n  Close to work.\n"),
        ("a\n\nb\n\n\n", "note: |+\n  a\n\n  b\n\n\n"),
        ("  indented first\nsecond", "note: |2-\n    indented first\n  second\n"),
        ("\nstarts blank", "note: |-\n\n  starts blank\n"),
        ("", "note: \"\"\n"),
        ("crlf\r\nline", "note: \"crlf\\r\\nline\"\n"),
        ("a\n   \nb", "note: \"a\\n   \\nb\"\n"),
    ])
    func noteKeepsLeadingSpacesAndTrailingNewlines(note: String, written: String) throws {
        var scrap = Self.sample()
        scrap.note = Note(text: note, updated: scrap.created)
        let text = FrontmatterCodec.encode(scrap)
        #expect(text.contains("\n" + written + "noteUpdated: "))
        #expect(try FrontmatterCodec.decode(text).note?.text == note)
    }

    @Test(arguments: [
        Locator.app,
        .url(URL(string: "https://example.com/a?b=c#d")!),
        .messageID("abc+/=%25@example.com"),
        .file(path: "/Users/me/Lease 2026.pdf", bookmark: Data([0, 1, 254, 255])),
        .screenRect(ScreenRect(x: -12.5, y: 0, width: 640, height: 480.25)),
        .other("note-42"),
    ])
    func locatorRoundTrips(locator: Locator) throws {
        var scrap = Self.sample()
        scrap.reference.locator = locator
        switch locator {
        case .url: scrap.reference.provider = .safari
        case .messageID: scrap.reference.provider = .mail
        case .screenRect: scrap.reference.provider = .screenshot
        case .other: scrap.reference.provider = ProviderID(rawValue: "notes")
        default: break
        }
        #expect(try FrontmatterCodec.decode(FrontmatterCodec.encode(scrap)) == scrap)
    }

    // MARK: - Unknown and reserved keys

    @Test func unknownKeysSurviveRoundTrip() throws {
        let original = try FrontmatterCodec.decode(try Fixtures.text("obsidian-edited.md"))
        #expect(
            original.extraFrontmatter == [
                FrontmatterEntry(key: "tags", value: .list([.string("apartment"), .string("follow-up")])),
                FrontmatterEntry(key: "status", value: .string("shortlisted")),
                FrontmatterEntry(key: "aliases", value: .list([.string("Elm St"), .string("2BR")])),
                FrontmatterEntry(key: "rating", value: .scalar("4.5")),
                FrontmatterEntry(key: "due", value: .scalar("2026-10-15")),
                FrontmatterEntry(key: "reviewed", value: .scalar("true")),
                FrontmatterEntry(key: "empty", value: .null),
            ])
        // Read, modify, write: a note edit keeps every unknown key, in order, with its type.
        var edited = original
        edited.note = Note(text: "Ask about parking.", updated: original.updated)
        let rewritten = try FrontmatterCodec.decode(FrontmatterCodec.encode(edited))
        #expect(rewritten.note == edited.note)
        #expect(rewritten.extraFrontmatter == original.extraFrontmatter)
    }

    /// An editor may leave an emptied property as `key:`; optional keys then take their defaults.
    @Test func emptyOptionalKeysReadAsMissing() throws {
        let text = try Fixtures.text("design-example.md")
            .replacingOccurrences(of: "title: \"2BR on Elm St\"", with: "title:")
            .replacingOccurrences(of: "pinned: false", with: "pinned:")
            .replacingOccurrences(of: "  window: \"2BR Apartment - Zillow\"", with: "  window: ~")
            .replacingOccurrences(of: "noteUpdated: 2026-09-29T14:05:40Z", with: "noteUpdated:\naiExcluded:")
        let scrap = try FrontmatterCodec.decode(text)
        #expect(scrap.title == "")
        #expect(scrap.pinned == false)
        #expect(scrap.reference.window == nil)
        #expect(scrap.note?.updated == scrap.updated)
        #expect(scrap.aiExcluded == false)
    }

    @Test func emptyRequiredKeyIsMissing() throws {
        let text = try Fixtures.text("design-example.md").replacingOccurrences(of: "board: \"a3\"", with: "board:")
        #expect(throws: CodecError.missingKey("board")) { try FrontmatterCodec.decode(text) }
    }

    /// The schema is checked before the rest is parsed, so a newer file that uses syntax this
    /// version can't read still reports that it's newer.
    @Test func newerSchemaIsReportedBeforeSyntax() throws {
        let text = try Fixtures.text("unsupported/anchor.md").replacingOccurrences(of: "schema: 1", with: "schema: 3")
        #expect(throws: CodecError.newerSchema(3)) { try FrontmatterCodec.decode(text) }
    }

    @Test func byteOrderMarkIsSkipped() throws {
        let text = try Fixtures.text("design-example.md")
        let scrap = try FrontmatterCodec.decode("\u{FEFF}" + text)
        #expect(FrontmatterCodec.encode(scrap) == text)
    }

    /// Unknown keys must be writable back unchanged; a key the writer couldn't reproduce is an
    /// error on read rather than a key silently lost on the next save.
    @Test(arguments: ["-dash: x", "tab\tinside: x", ".key\u{7}: x"])
    func keysTheWriterCantReproduceAreRejected(line: String) throws {
        let text = try Fixtures.text("design-example.md")
            .replacingOccurrences(
                of: "noteUpdated: 2026-09-29T14:05:40Z\n", with: "noteUpdated: 2026-09-29T14:05:40Z\n\(line)\n")
        #expect(throws: CodecError.invalidSyntax(line: 21)) { try FrontmatterCodec.decode(text) }
    }

    @Test func derivedFromAndAIExcludedRoundTrip() throws {
        var scrap = Self.sample()
        scrap.derivedFrom = [ScrapID(), ScrapID()]
        scrap.aiExcluded = true
        let text = FrontmatterCodec.encode(scrap)
        #expect(text.contains("\nderivedFrom:\n  - \"\(scrap.derivedFrom[0].stringValue)\"\n"))
        #expect(text.contains("\naiExcluded: true\n"))
        let decoded = try FrontmatterCodec.decode(text)
        #expect(decoded.derivedFrom == scrap.derivedFrom)
        #expect(decoded.aiExcluded)
    }

    @Test func emptyReservedKeysAreNotWritten() {
        let text = FrontmatterCodec.encode(Self.sample())
        #expect(!text.contains("derivedFrom"))
        #expect(!text.contains("aiExcluded"))
        #expect(!text.contains("window:"))
        #expect(!text.contains("note"))
    }

    // MARK: - Reading

    @Test func bodyIsKeptByteForByte() throws {
        var scrap = Self.sample()
        scrap.body = "---\nnot: frontmatter\r\n\n  ...\n"
        let decoded = try FrontmatterCodec.decode(FrontmatterCodec.encode(scrap))
        #expect(Array(decoded.body.utf8) == Array(scrap.body.utf8))
    }

    @Test func crlfFrontmatterIsAccepted() throws {
        let text = try Fixtures.text("design-example.md")
        let crlf = text.replacingOccurrences(of: "\n", with: "\r\n")
        let scrap = try FrontmatterCodec.decode(crlf)
        #expect(scrap.title == "2BR on Elm St")
        #expect(scrap.note?.text == "Close to work, but ask about parking.\n")
        #expect(scrap.body == "2BR, 850 sq ft, $2,400/mo, in-unit laundry\r\n")
    }

    @Test func invalidUTF8IsRejected() {
        var data = Data("---\ntitle: \"".utf8)
        data.append(0xFF)
        #expect(throws: CodecError.invalidUTF8) { try FrontmatterCodec.decode(data) }
    }

    @Test func missingDelimitersAreRejected() {
        #expect(throws: CodecError.missingOpeningDelimiter) { try FrontmatterCodec.decode("title: \"x\"\n") }
        #expect(throws: CodecError.missingClosingDelimiter) { try FrontmatterCodec.decode("---\nschema: 1\n") }
    }

    @Test func missingRequiredKeyIsRejected() throws {
        let text = try Fixtures.text("design-example.md").replacingOccurrences(of: "board: \"a3\"\n", with: "")
        #expect(throws: CodecError.missingKey("board")) { try FrontmatterCodec.decode(text) }
    }

    @Test func duplicateKeyIsRejected() throws {
        let text = try Fixtures.text("design-example.md")
            .replacingOccurrences(of: "pinned: false\n", with: "pinned: false\npinned: true\n")
        #expect(throws: CodecError.duplicateKey("pinned", line: 7)) { try FrontmatterCodec.decode(text) }
    }

    @Test func invalidKnownValueIsRejected() throws {
        let text = try Fixtures.text("design-example.md").replacingOccurrences(
            of: "board: \"a3\"", with: "board: \"a30\"")
        #expect(throws: CodecError.invalidValue(key: "board", line: 7)) { try FrontmatterCodec.decode(text) }
    }

    @Test func rejectsNewerSchema() throws {
        let text = try Fixtures.text("design-example.md").replacingOccurrences(of: "schema: 1", with: "schema: 2")
        #expect(throws: CodecError.newerSchema(2)) { try FrontmatterCodec.decode(text) }
    }

    @Test(arguments: [
        ("unsupported/anchor.md", UnsupportedConstruct.anchor, 5),
        ("unsupported/alias.md", .alias, 5),
        ("unsupported/tag.md", .tag, 5),
        ("unsupported/flow-map.md", .flowMap, 15),
        ("unsupported/folded-scalar.md", .foldedScalar, 15),
        ("unsupported/nested-map.md", .nestedMap, 15),
        ("unsupported/comment.md", .comment, 15),
        ("unsupported/document-marker.md", .documentMarker, 10),
    ])
    func rejectsUnsupportedYAML(fixture: String, construct: UnsupportedConstruct, line: Int) throws {
        let text = try Fixtures.text(fixture)
        #expect(throws: CodecError.unsupportedSyntax(line: line, construct: construct)) {
            try FrontmatterCodec.decode(text)
        }
    }

    /// The same, for constructs that only need one line to show.
    @Test(arguments: [
        ("tags:\n  - [a, b]", UnsupportedConstruct.nestedList),
        ("tags:\n  - - a", .nestedList),
        ("tags:\n  - key: value", .nestedMap),
        ("status: one\n  two", .multilineScalar),
        ("status: \"one\n  two\"", .multilineScalar),
        ("status: value # note", .comment),
        ("status: value: more", .nestedMap),
        ("? status\n: value", .complexKey),
        ("\"status\": value", .complexKey),
        ("%YAML 1.2", .directive),
        ("status:\n\t- a", .tabIndentation),
        ("aliases: [a, {b: c}]", .flowMap),
        ("reference2:\n  a:\n    b: c", .nestedMap),
    ])
    func rejectsUnsupportedInlineYAML(extra: String, construct: UnsupportedConstruct) throws {
        let text = try Fixtures.text("design-example.md")
            .replacingOccurrences(
                of: "noteUpdated: 2026-09-29T14:05:40Z\n", with: "noteUpdated: 2026-09-29T14:05:40Z\n\(extra)\n")
        let error = #expect(throws: CodecError.self) { try FrontmatterCodec.decode(text) }
        guard case .unsupportedSyntax(_, let found) = error else {
            Issue.record("expected unsupportedSyntax, got \(String(describing: error))")
            return
        }
        #expect(found == construct)
    }

    // MARK: - Helpers

    static func sample() -> Scrap {
        let date = Date(timeIntervalSince1970: 1_790_690_531)
        return Scrap(
            id: ScrapID(string: "8f3a0c2d-5d0f-4c8e-9a51-3c1e7a2b71e4") ?? ScrapID(),
            kind: .text,
            title: "2BR on Elm St",
            body: "2BR, 850 sq ft\n",
            board: Rank(rawValue: "a3") ?? .after(nil),
            created: date,
            updated: date,
            reference: Reference(
                provider: .fallback,
                app: AppIdentity(bundleID: "com.apple.TextEdit"),
                locator: .app,
                label: "TextEdit",
                fingerprint: Fingerprint.text("2BR, 850 sq ft")
            )
        )
    }
}
