import SQLite3

/// The system SQLite library the index links against.
public enum SQLiteLibrary {
    /// The library version, for example "3.46.1".
    public static var version: String {
        String(cString: sqlite3_libversion())
    }
}
