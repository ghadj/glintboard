import Foundation
import SQLite3

/// Why the index couldn't do something.
public enum IndexError: Error, Equatable, Sendable {
    /// The database file couldn't be opened or created.
    case cannotOpen(String)
    /// SQLite reported an error.
    case sqlite(code: Int32, message: String)
    /// `open()` hasn't been called, or it failed.
    case notOpen
}

/// A value bound to, or read from, an SQL statement.
enum SQLValue: Equatable {
    case null
    case integer(Int64)
    case real(Double)
    case text(String)
}

/// A small wrapper over one SQLite connection, through the C API. Not `Sendable`: only the
/// index actor owns and uses it.
final class SQLiteConnection {
    private var handle: OpaquePointer?

    /// Copies bound strings, since they don't outlive the call (the C macro doesn't import).
    private static var transient: sqlite3_destructor_type { unsafeBitCast(-1, to: sqlite3_destructor_type.self) }

    init(path: String) throws(IndexError) {
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_NOMUTEX
        let code = sqlite3_open_v2(path, &handle, flags, nil)
        guard code == SQLITE_OK else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "code \(code)"
            sqlite3_close_v2(handle)
            handle = nil
            throw .cannotOpen(message)
        }
    }

    deinit {
        sqlite3_close_v2(handle)
    }

    /// Runs one or more statements that return no rows.
    func execute(_ sql: String) throws(IndexError) {
        guard sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK else { throw lastError() }
    }

    /// Runs one statement with bound values, calling `row` for each result row.
    func query(_ sql: String, _ values: [SQLValue] = [], row: (Row) throws(IndexError) -> Void) throws(IndexError) {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw lastError()
        }
        defer { sqlite3_finalize(statement) }
        for (offset, value) in values.enumerated() {
            let index = Int32(offset + 1)
            let code: Int32
            switch value {
            case .null: code = sqlite3_bind_null(statement, index)
            case .integer(let number): code = sqlite3_bind_int64(statement, index, number)
            case .real(let number): code = sqlite3_bind_double(statement, index, number)
            // An explicit byte count, so text containing U+0000 isn't cut short.
            case .text(let text):
                code = sqlite3_bind_text(statement, index, text, Int32(text.utf8.count), Self.transient)
            }
            guard code == SQLITE_OK else { throw lastError() }
        }
        while true {
            switch sqlite3_step(statement) {
            case SQLITE_ROW: try row(Row(statement: statement))
            case SQLITE_DONE: return
            default: throw lastError()
            }
        }
    }

    /// Runs one statement with bound values and no result rows.
    func run(_ sql: String, _ values: [SQLValue] = []) throws(IndexError) {
        try query(sql, values) { _ throws(IndexError) in }
    }

    /// The first column of the first row, as text.
    func scalarText(_ sql: String, _ values: [SQLValue] = []) throws(IndexError) -> String? {
        var result: String?
        try query(sql, values) { row throws(IndexError) in
            if result == nil { result = row.text(0) }
        }
        return result
    }

    var lastInsertRowID: Int64 { sqlite3_last_insert_rowid(handle) }

    /// Runs `body` in a transaction, rolled back if it throws.
    func transaction(_ body: () throws(IndexError) -> Void) throws(IndexError) {
        try execute("BEGIN IMMEDIATE")
        do {
            try body()
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    private func lastError() -> IndexError {
        guard let handle else { return .notOpen }
        return .sqlite(code: sqlite3_errcode(handle), message: String(cString: sqlite3_errmsg(handle)))
    }

    /// One result row; valid only inside the `query` callback.
    struct Row {
        fileprivate let statement: OpaquePointer

        func integer(_ column: Int32) -> Int64 { sqlite3_column_int64(statement, column) }
        func real(_ column: Int32) -> Double { sqlite3_column_double(statement, column) }

        func text(_ column: Int32) -> String? {
            guard let bytes = sqlite3_column_text(statement, column) else { return nil }
            // By byte count (asked for after the text, as SQLite requires), not up to a NUL.
            let count = Int(sqlite3_column_bytes(statement, column))
            return String(decoding: UnsafeBufferPointer(start: bytes, count: count), as: UTF8.self)
        }
    }
}
