import Foundation
import SQLite3
import ScrapModel

/// The search index: a SQLite cache of the scrap files, rebuilt whenever it can't be used. It
/// holds what cards and search need, plus reference health, which lives nowhere else. One
/// connection, owned by this actor.
public actor ScrapIndex {
    public enum OpenResult: Sendable, Equatable {
        /// There was no index; an empty one was made.
        case created
        case opened
        /// The index couldn't be used, so it was deleted and made again, empty.
        case rebuilt(RebuildReason)
    }

    public enum RebuildReason: Sendable, Equatable {
        /// SQLite couldn't open the file.
        case unreadable
        /// The file isn't a database, or failed its integrity check.
        case corrupt
        /// It was built for another index schema version.
        case otherVersion(Int32)
        /// It was built with the other full-text engine.
        case otherEngine
    }

    public let databaseURL: URL
    public private(set) var engine: FullTextEngine = .fts5
    private let forcedEngine: FullTextEngine?
    private var connection: SQLiteConnection?

    public init(databaseURL: URL) {
        self.init(databaseURL: databaseURL, engine: nil)
    }

    /// `engine` forces a full-text engine; tests use it to run on FTS4.
    init(databaseURL: URL, engine: FullTextEngine?) {
        self.databaseURL = databaseURL
        forcedEngine = engine
    }

    // MARK: - Opening

    /// Opens the index, creating it if it's missing and rebuilding it (empty) if it's
    /// unreadable, corrupt, or from another schema version or engine. Reconciliation then fills
    /// it from the files.
    @discardableResult
    public func open() throws(IndexError) -> OpenResult {
        close()
        // Not `??`: its autoclosure would lose the typed error.
        if let forcedEngine {
            engine = forcedEngine
        } else {
            engine = try Self.availableEngine()
        }
        let path = databaseURL.path(percentEncoded: false)
        guard FileManager.default.fileExists(atPath: path) else {
            // A write-ahead log left without its database would be replayed into the new one.
            Self.removeFiles(at: path)
            connection = try create(at: path)
            return .created
        }

        var reason = RebuildReason.corrupt
        do throws(IndexError) {
            let existing = try SQLiteConnection(path: path)
            do throws(IndexError) {
                if let problem = try problem(with: existing) {
                    reason = problem
                } else {
                    try configure(existing)
                    connection = existing
                    return .opened
                }
            } catch {
                // Only damage justifies deleting the index. A busy, locked, or failing database
                // (another reader recovering the log, say) may be healthy, so that's an error.
                guard Self.meansDamaged(error) else { throw error }
                reason = .corrupt
            }
        } catch {
            guard case .cannotOpen = error else { throw error }
            reason = .unreadable
        }
        // The rejected connection is closed by now; remove the files and start again.
        Self.removeFiles(at: path)
        connection = try create(at: path)
        return .rebuilt(reason)
    }

    /// Not a database, corrupt, or missing its tables (`SQLITE_ERROR`, "no such table").
    private static func meansDamaged(_ error: IndexError) -> Bool {
        guard case .sqlite(let code, _) = error else { return false }
        return code == SQLITE_CORRUPT || code == SQLITE_NOTADB || code == SQLITE_ERROR
    }

    private static func removeFiles(at path: String) {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(atPath: path + suffix)
        }
    }

    public func close() {
        connection = nil
    }

    private func problem(with existing: SQLiteConnection) throws(IndexError) -> RebuildReason? {
        guard try existing.scalarText("PRAGMA quick_check") == "ok" else { return .corrupt }
        let version = Int32(try existing.scalarText("PRAGMA user_version") ?? "") ?? 0
        guard version == IndexSchema.version else { return .otherVersion(version) }
        let built = try existing.scalarText("SELECT value FROM meta WHERE key = 'engine'")
        guard built == engine.rawValue else { return .otherEngine }
        return nil
    }

    private func create(at path: String) throws(IndexError) -> SQLiteConnection {
        let created = try SQLiteConnection(path: path)
        try configure(created)
        try created.transaction { () throws(IndexError) in
            try created.execute(IndexSchema.create(engine: engine))
        }
        return created
    }

    /// WAL lets readers (the MCP helper, later) work alongside the one writer. Foreign keys are
    /// per connection, and make health rows go with their scrap.
    private func configure(_ connection: SQLiteConnection) throws(IndexError) {
        try connection.execute("PRAGMA journal_mode = WAL; PRAGMA foreign_keys = ON;")
    }

    /// FTS5 if the system SQLite was built with it, otherwise FTS4.
    private static func availableEngine() throws(IndexError) -> FullTextEngine {
        let memory = try SQLiteConnection(path: ":memory:")
        var hasFTS5 = false
        try memory.query("PRAGMA compile_options") { row throws(IndexError) in
            if row.text(0) == "ENABLE_FTS5" { hasFTS5 = true }
        }
        return hasFTS5 ? .fts5 : .fts4
    }

    private func database() throws(IndexError) -> SQLiteConnection {
        guard let connection else { throw .notOpen }
        return connection
    }

    // MARK: - Following the library

    /// Brings the index in line with one change from the store.
    public func apply(_ change: LibraryChange) throws(IndexError) {
        switch change {
        case .saved(let scrap, let file), .updated(let scrap, let file):
            try upsert(scrap, file: file)
        case .removed(let path, _), .problem(let path, _):
            // An unreadable file no longer shows its old content either.
            try removeRow(atPath: path)
        case .rescanNeeded:
            break
        }
    }

    private func upsert(_ scrap: Scrap, file: ScrapFileInfo) throws(IndexError) {
        let db = try database()
        try db.transaction { () throws(IndexError) in
            let byID = try rowID(db, "id = ?", .text(scrap.id.stringValue))
            let byPath = try rowID(db, "path = ?", .text(file.path))
            // Another scrap's row at this path is stale: the file now holds this scrap.
            if let byPath, byPath != byID { try deleteRow(db, byPath) }

            let collection = String(file.path.split(separator: "/").first ?? "")
            let fields: [SQLValue] = [
                .text(collection), .text(file.path), .real(file.modified.timeIntervalSinceReferenceDate),
                .integer(Int64(file.size)),
                .text(scrap.kind.rawValue), .text(scrap.title), .text(scrap.reference.label),
                .text(scrap.reference.provider.rawValue), .integer(scrap.pinned ? 1 : 0), .text(scrap.board.rawValue),
                .real(scrap.created.timeIntervalSinceReferenceDate),
                .real(scrap.updated.timeIntervalSinceReferenceDate),
                .text(scrap.reference.fingerprint.rawValue), Self.locator(scrap.reference.locator),
                .text(String(scrap.body.prefix(300))), scrap.asset.map { SQLValue.text($0.path) } ?? .null,
                .integer(scrap.note == nil ? 0 : 1),
            ]
            let rowID: Int64
            if let byID {
                // Updated in place, so its health row stays.
                try db.run(
                    """
                    UPDATE scraps SET collection = ?, path = ?, mtime = ?, size = ?, kind = ?, title = ?, label = ?,
                      provider = ?, pinned = ?, board = ?, created = ?, updated = ?, fingerprint = ?, locator = ?,
                      preview = ?, asset = ?, has_note = ?
                    WHERE rowid = ?
                    """, fields + [.integer(byID)])
                try db.run("DELETE FROM scraps_fts WHERE rowid = ?", [.integer(byID)])
                rowID = byID
            } else {
                try db.run(
                    """
                    INSERT INTO scraps (id, collection, path, mtime, size, kind, title, label, provider, pinned,
                      board, created, updated, fingerprint, locator, preview, asset, has_note)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """, [.text(scrap.id.stringValue)] + fields)
                rowID = db.lastInsertRowID
            }
            try db.run(
                "INSERT INTO scraps_fts (rowid, title, body, note, label, window_title) VALUES (?, ?, ?, ?, ?, ?)",
                [
                    .integer(rowID), .text(scrap.title), .text(scrap.body), .text(scrap.note?.text ?? ""),
                    .text(scrap.reference.label), .text(scrap.reference.window ?? ""),
                ])
        }
    }

    private func removeRow(atPath path: String) throws(IndexError) {
        let db = try database()
        try db.transaction { () throws(IndexError) in
            if let row = try rowID(db, "path = ?", .text(path)) { try deleteRow(db, row) }
        }
    }

    private func rowID(_ db: SQLiteConnection, _ condition: String, _ value: SQLValue) throws(IndexError) -> Int64? {
        var result: Int64?
        try db.query("SELECT rowid FROM scraps WHERE \(condition)", [value]) { row throws(IndexError) in
            result = row.integer(0)
        }
        return result
    }

    /// Its health row goes with it (`ON DELETE CASCADE`).
    private func deleteRow(_ db: SQLiteConnection, _ rowID: Int64) throws(IndexError) {
        try db.run("DELETE FROM scraps_fts WHERE rowid = ?", [.integer(rowID)])
        try db.run("DELETE FROM scraps WHERE rowid = ?", [.integer(rowID)])
    }

    /// The locator as stored for duplicate checks: a URL, Message-ID, path, or rectangle.
    private static func locator(_ locator: Locator) -> SQLValue {
        switch locator {
        case .app: .null
        case .url(let url): .text(url.absoluteString)
        case .messageID(let messageID): .text(messageID)
        case .file(let path, _): .text(path)
        case .screenRect(let rect): .text("\(rect.x),\(rect.y),\(rect.width),\(rect.height)")
        case .other(let raw): .text(raw)
        }
    }

    // MARK: - Queries

    /// Scraps matching the query, most recently updated first.
    public func search(_ query: SearchQuery) throws(IndexError) -> [ScrapID] {
        let db = try database()
        guard let match = query.matchExpression(for: engine) else { return [] }
        var sql = """
            SELECT s.id FROM scraps_fts JOIN scraps s ON s.rowid = scraps_fts.rowid
            WHERE scraps_fts MATCH ?
            """
        var values: [SQLValue] = [.text(match)]
        if let collection = query.collection {
            sql += " AND s.collection = ?"
            values.append(.text(collection.rawValue))
        }
        sql += " ORDER BY s.updated DESC, s.rowid DESC"
        var ids: [ScrapID] = []
        try db.query(sql, values) { row throws(IndexError) in
            if let id = row.text(0).flatMap(ScrapID.init(string:)) { ids.append(id) }
        }
        return ids
    }

    /// The cards of a collection, most recently updated first.
    public func cards(in collection: CollectionName) throws(IndexError) -> [ScrapSummary] {
        let db = try database()
        var cards: [ScrapSummary] = []
        try db.query(
            """
            SELECT id, collection, path, kind, title, preview, label, provider, pinned, board, created, updated,
              asset, has_note
            FROM scraps WHERE collection = ? ORDER BY updated DESC, rowid DESC
            """, [.text(collection.rawValue)]
        ) { row throws(IndexError) in
            guard let id = row.text(0).flatMap(ScrapID.init(string:)) else { return }
            cards.append(
                ScrapSummary(
                    id: id, collection: row.text(1) ?? "", path: row.text(2) ?? "",
                    kind: row.text(3).flatMap(ScrapKind.init(rawValue:)) ?? .text, title: row.text(4) ?? "",
                    preview: row.text(5) ?? "", label: row.text(6) ?? "",
                    provider: ProviderID(rawValue: row.text(7) ?? ""), pinned: row.integer(8) != 0,
                    board: row.text(9).flatMap(Rank.init(rawValue:)),
                    created: Date(timeIntervalSinceReferenceDate: row.real(10)),
                    updated: Date(timeIntervalSinceReferenceDate: row.real(11)),
                    asset: row.text(12), hasNote: row.integer(13) != 0))
        }
        return cards
    }

    /// Path, modification date, and size of every indexed file, for reconciliation.
    public func fileStates() throws(IndexError) -> [String: ScrapFileInfo] {
        let db = try database()
        var states: [String: ScrapFileInfo] = [:]
        try db.query("SELECT path, mtime, size FROM scraps") { row throws(IndexError) in
            guard let path = row.text(0) else { return }
            states[path] = ScrapFileInfo(
                path: path, modified: Date(timeIntervalSinceReferenceDate: row.real(1)), size: Int(row.integer(2)))
        }
        return states
    }

    /// The highest board rank in a collection, for appending new scraps.
    public func lastRank(in collection: CollectionName) throws(IndexError) -> Rank? {
        let db = try database()
        return try db.scalarText(
            "SELECT board FROM scraps WHERE collection = ? ORDER BY board DESC LIMIT 1", [.text(collection.rawValue)]
        ).flatMap(Rank.init(rawValue:))
    }

    // MARK: - Reference health (index only; never written to scrap files)

    public func health(of id: ScrapID) throws(IndexError) -> ReferenceHealth? {
        let db = try database()
        var health: ReferenceHealth?
        try db.query("SELECT status, last_checked FROM health WHERE id = ?", [.text(id.stringValue)]) {
            row throws(IndexError) in
            guard let status = row.text(0).flatMap(ReferenceStatus.init(rawValue:)) else { return }
            health = ReferenceHealth(status: status, lastChecked: Date(timeIntervalSinceReferenceDate: row.real(1)))
        }
        return health
    }

    public func setHealth(_ health: ReferenceHealth, for id: ScrapID) throws(IndexError) {
        let db = try database()
        try db.run(
            """
            INSERT INTO health (id, status, last_checked) VALUES (?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET status = excluded.status, last_checked = excluded.last_checked
            """,
            [
                .text(id.stringValue), .text(health.status.rawValue),
                .real(health.lastChecked.timeIntervalSinceReferenceDate),
            ])
    }
}
