import Foundation
import ScrapModel

/// Reads and writes a collection's `.collection.json`: `schema` (its format version), `order`
/// (an integer) and `created` (an ISO 8601 UTC date), plus any keys this version doesn't know,
/// which are kept.
public enum CollectionFile {
    /// The `.collection.json` format version this version reads and writes.
    public static let currentSchema = 1

    /// A file without `schema` (one written by hand, say) is read as schema 1. A newer schema
    /// is an error, so this version never rewrites a newer file.
    public static func decode(_ data: Data, name: String) throws(StoreError) -> CollectionInfo {
        let path = name + "/" + LibraryLayout.collectionFileName
        guard var fields = try? JSONDecoder().decode([String: JSONValue].self, from: data) else {
            throw .invalidCollectionFile(path: path)
        }
        switch fields.removeValue(forKey: "schema") {
        case nil:
            break
        case .integer(let schema)? where schema > currentSchema:
            throw .newerCollectionSchema(path: path, schema)
        case .integer(let schema)? where schema >= 1:
            break
        default:
            throw .invalidCollectionFile(path: path)
        }
        let orderValue = fields.removeValue(forKey: "order")
        let createdValue = fields.removeValue(forKey: "created")
        guard case .integer(let order)? = orderValue, case .string(let createdText)? = createdValue,
            let created = parseDate(createdText)
        else { throw .invalidCollectionFile(path: path) }
        return CollectionInfo(name: name, order: order, created: created, extra: fields)
    }

    /// Pretty-printed with sorted keys, so the output is stable. Dates are whole seconds, and
    /// `schema` is always the current one.
    public static func encode(_ info: CollectionInfo) throws(StoreError) -> Data {
        var fields = info.extra
        fields["schema"] = .integer(currentSchema)
        fields["order"] = .integer(info.order)
        let whole = Date(timeIntervalSince1970: info.created.timeIntervalSince1970.rounded(.down))
        fields["created"] = .string(whole.formatted(.iso8601))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(fields) else {
            throw .writeFailed(path: info.name + "/" + LibraryLayout.collectionFileName)
        }
        return data + Data("\n".utf8)
    }

    private static func parseDate(_ text: String) -> Date? {
        if let date = try? Date.ISO8601FormatStyle().parse(text) { return date }
        return try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(text)
    }
}
