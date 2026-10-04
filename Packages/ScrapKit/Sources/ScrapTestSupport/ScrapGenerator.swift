import Foundation
import ScrapModel

/// Builds random but reproducible scraps for codec round-trip tests. Strings mix the
/// characters most likely to break a YAML writer: emoji, combining marks, right-to-left and
/// CJK text, YAML indicators, quotes, backslashes, control characters, and leading, trailing,
/// and repeated whitespace. Dates are whole seconds, as the writer stores them.
public struct ScrapGenerator {
    private var random: SeededRandom

    public init(seed: UInt64) {
        random = SeededRandom(seed: seed)
    }

    public mutating func scrap() -> Scrap {
        let created = date()
        let hasNote = bool()
        return Scrap(
            id: id(),
            kind: ScrapKind.allCases.randomElement(using: &random) ?? .text,
            title: text(maxFragments: 6, allowNewlines: bool()),
            body: body(),
            asset: bool() ? AssetRef(path: "assets/" + text(maxFragments: 3, allowNewlines: false)) : nil,
            pinned: bool(),
            board: rank(),
            created: created,
            updated: created.addingTimeInterval(Double(Int.random(in: 0...100_000, using: &random))),
            reference: reference(),
            note: hasNote ? Note(text: noteText(), updated: date()) : nil,
            derivedFrom: (0..<Int.random(in: 0...3, using: &random)).map { _ in id() },
            aiExcluded: bool(),
            extraFrontmatter: extraEntries()
        )
    }

    // MARK: - Pieces

    private static let fragments: [String] = [
        "apartment", "2BR", "Elm St", "zillow.com", "a", "Z", "0", "42", "-1", "4.5",
        "🏠", "👩‍👩‍👧", "🇨🇾", "e\u{301}", "\u{E9}", "公寓", "شقة", "דירה", "Ελληνικά",
        ":", ": ", " :", "#", " #", "# ", "\"", "'", "\\", "\\n", "/", "-", "- ", "---", "...",
        "[", "]", "{", "}", ",", "&", "*", "!", "!!str", "|", ">", "%", "@", "`", "?", "~",
        "null", "true", "false", "yes", "2026-10-03", "\t", "\u{A0}", "\u{2028}", "\u{FEFF}",
        "\u{7}", "\u{1B}", "\u{85}", "\u{200B}", "\u{FFFE}",
    ]

    private mutating func bool() -> Bool { Bool.random(using: &random) }

    private mutating func id() -> ScrapID {
        var bytes = [UInt8](repeating: 0, count: 16)
        for index in bytes.indices { bytes[index] = UInt8.random(in: 0...255, using: &random) }
        let uuid = UUID(
            uuid: (
                bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
            ))
        return ScrapID(raw: uuid)
    }

    private mutating func date() -> Date {
        // 2000-01-01 to about 2100, whole seconds.
        Date(timeIntervalSince1970: Double(Int.random(in: 946_684_800...4_102_444_800, using: &random)))
    }

    private mutating func rank() -> Rank {
        var rank = Rank.after(nil)
        for _ in 0..<Int.random(in: 0...200, using: &random) {
            rank = bool() ? Rank.after(rank) : Rank.between(Rank.before(rank), rank)
        }
        return rank
    }

    /// Joined fragments, optionally with spaces, newlines, and runs of whitespace between them.
    private mutating func text(maxFragments: Int, allowNewlines: Bool) -> String {
        var result = ""
        for _ in 0..<Int.random(in: 0...maxFragments, using: &random) {
            result += Self.fragments.randomElement(using: &random) ?? ""
            switch Int.random(in: 0...5, using: &random) {
            case 0: result += " "
            case 1: result += "  "
            case 2 where allowNewlines: result += "\n"
            default: break
            }
        }
        if bool() { result = " " + result }
        return result
    }

    private mutating func body() -> String {
        var lines: [String] = []
        for _ in 0..<Int.random(in: 0...6, using: &random) {
            lines.append(text(maxFragments: 5, allowNewlines: false))
        }
        let separator = Int.random(in: 0...4, using: &random) == 0 ? "\r\n" : "\n"
        return lines.joined(separator: separator) + (bool() ? separator : "")
    }

    /// Multi-line notes, with and without trailing newlines, sometimes starting with blank
    /// lines or a space, sometimes containing a carriage return or whitespace-only lines.
    private mutating func noteText() -> String {
        var lines: [String] = []
        for _ in 0..<Int.random(in: 1...5, using: &random) {
            switch Int.random(in: 0...9, using: &random) {
            case 0: lines.append("")
            case 1: lines.append("   ")
            default: lines.append(text(maxFragments: 5, allowNewlines: false))
            }
        }
        var note = lines.joined(separator: Int.random(in: 0...9, using: &random) == 0 ? "\r\n" : "\n")
        note += String(repeating: "\n", count: Int.random(in: 0...3, using: &random))
        return note
    }

    private mutating func reference() -> Reference {
        let fingerprint = Fingerprint.text(text(maxFragments: 4, allowNewlines: true))
        let appName = ["Safari", "Mail", "Finder", "Te xt"].randomElement(using: &random) ?? "Safari"
        let app = bool() ? AppIdentity(bundleID: "com.example." + appName) : nil
        let window = bool() ? text(maxFragments: 4, allowNewlines: false) : nil
        let label = text(maxFragments: 3, allowNewlines: false)
        let deepLink = bool() ? URL(string: "https://example.com/page#:~:text=a,b") : nil
        let (provider, locator): (ProviderID, Locator)
        switch Int.random(in: 0...5, using: &random) {
        case 0:
            var components = URLComponents(string: "https://www.example.com/listing/") ?? URLComponents()
            components.path += String(Int.random(in: 0...99_999, using: &random))
            components.percentEncodedQuery = "q=a%20b&x=1"
            provider = .safari
            locator = components.url.map(Locator.url) ?? .app
        case 1:
            provider = .mail
            locator = .messageID("abc+/=%" + String(Int.random(in: 0...9_999, using: &random)) + "@mail.example.com")
        case 2:
            var bookmark = Data()
            for _ in 0..<Int.random(in: 1...64, using: &random) {
                bookmark.append(UInt8.random(in: 0...255, using: &random))
            }
            provider = .files
            locator = .file(
                path: "/Users/me/" + text(maxFragments: 3, allowNewlines: false) + ".pdf", bookmark: bookmark)
        case 3:
            provider = .screenshot
            locator = .screenRect(
                ScreenRect(
                    x: Double(Int.random(in: -2_000...2_000, using: &random)) / 4,
                    y: Double(Int.random(in: -2_000...2_000, using: &random)) / 4,
                    width: Double(Int.random(in: 1...4_000, using: &random)) / 2,
                    height: Double(Int.random(in: 1...4_000, using: &random)) / 2
                ))
        case 4:
            provider = ProviderID(rawValue: bool() ? "notes" : "Notes App")
            locator = .other("note-" + text(maxFragments: 2, allowNewlines: false))
        default:
            provider = .fallback
            locator = .app
        }
        return Reference(
            provider: provider, app: app, window: window, locator: locator, deepLink: deepLink,
            label: label, fingerprint: fingerprint)
    }

    private static let extraKeys = ["tags", "aliases", "status", "rating", "due", "my key", "cssclasses", "source-url"]
    private static let scalars = [
        "4.5", "5", "-3", "+7", "1e3", "0x1F", ".inf", "true", "false", "null", "~", "2026-10-03",
        "2026-10-03T14:30", "2026-10-03T14:30:00+02:00", "2026-10-03 14:30:00Z",
    ]

    private mutating func extraValue(allowList: Bool) -> FrontmatterValue {
        switch Int.random(in: 0...(allowList ? 3 : 2), using: &random) {
        case 0: return .string(text(maxFragments: 4, allowNewlines: bool()))
        case 1: return .scalar(Self.scalars.randomElement(using: &random) ?? "5")
        case 2: return .null
        default:
            var items: [FrontmatterValue] = []
            for _ in 0..<Int.random(in: 0...4, using: &random) { items.append(extraValue(allowList: false)) }
            return .list(items)
        }
    }

    private mutating func extraEntries() -> [FrontmatterEntry] {
        let keys = Self.extraKeys.shuffled(using: &random).prefix(Int.random(in: 0...3, using: &random))
        return keys.map { FrontmatterEntry(key: $0, value: extraValue(allowList: true)) }
    }
}
