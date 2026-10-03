import Foundation

/// A scrap's stable identity, written as `id` in its frontmatter.
///
/// The frontmatter id is authoritative; file names only borrow `shortHex` for humans and are
/// never parsed back into an id.
public struct ScrapID: Hashable, Sendable {
    public let raw: UUID

    public init(raw: UUID = UUID()) {
        self.raw = raw
    }

    /// Accepts a UUID string in either case.
    public init?(string: String) {
        guard let uuid = UUID(uuidString: string) else { return nil }
        raw = uuid
    }

    /// The lowercase UUID string written to files.
    public var stringValue: String { raw.uuidString.lowercased() }

    /// The first four hex digits, used in file and asset names.
    public var shortHex: String { String(stringValue.prefix(4)) }
}

extension ScrapID: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let string = try container.decode(String.self)
        guard let id = ScrapID(string: string) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Not a UUID: \(string)")
        }
        self = id
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(stringValue)
    }
}

extension ScrapID: CustomStringConvertible {
    public var description: String { stringValue }
}
