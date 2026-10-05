/// The full-text engine the index uses: FTS5, or FTS4 where the system SQLite lacks FTS5.
public enum FullTextEngine: String, Sendable, CaseIterable {
    case fts5, fts4
}

/// The index's tables. The index is a rebuildable cache: when `version` changes, an old index
/// is deleted and rebuilt rather than migrated.
enum IndexSchema {
    static let version: Int32 = 1

    static func create(engine: FullTextEngine) -> String {
        """
        CREATE TABLE meta (
          key   TEXT PRIMARY KEY,
          value TEXT NOT NULL
        );
        INSERT INTO meta (key, value) VALUES ('engine', '\(engine.rawValue)');

        CREATE TABLE scraps (
          rowid       INTEGER PRIMARY KEY,
          id          TEXT NOT NULL UNIQUE,
          collection  TEXT NOT NULL,
          path        TEXT NOT NULL UNIQUE,
          mtime       REAL NOT NULL,
          size        INTEGER NOT NULL,
          kind        TEXT NOT NULL,
          title       TEXT NOT NULL,
          label       TEXT NOT NULL,
          provider    TEXT NOT NULL,
          pinned      INTEGER NOT NULL,
          board       TEXT NOT NULL,
          created     REAL NOT NULL,
          updated     REAL NOT NULL,
          fingerprint TEXT NOT NULL,
          locator     TEXT,
          preview     TEXT NOT NULL,
          asset       TEXT,
          has_note    INTEGER NOT NULL
        );
        CREATE INDEX scraps_recent ON scraps(collection, updated DESC);
        CREATE INDEX scraps_board  ON scraps(collection, board);
        CREATE INDEX scraps_dupes  ON scraps(collection, fingerprint, locator);

        CREATE TABLE health (
          id           TEXT PRIMARY KEY REFERENCES scraps(id) ON DELETE CASCADE,
          status       TEXT NOT NULL,
          last_checked REAL NOT NULL
        );

        \(fullText(engine: engine));

        PRAGMA user_version = \(version);
        """
    }

    /// Its rowid matches `scraps.rowid`. Diacritics are removed and two- and three-character
    /// prefixes are indexed, so search-as-you-type prefix queries are fast.
    private static func fullText(engine: FullTextEngine) -> String {
        switch engine {
        case .fts5:
            """
            CREATE VIRTUAL TABLE scraps_fts USING fts5(
              title, body, note, label, window_title,
              tokenize = 'unicode61 remove_diacritics 2',
              prefix = '2 3'
            )
            """
        case .fts4:
            """
            CREATE VIRTUAL TABLE scraps_fts USING fts4(
              title, body, note, label, window_title,
              tokenize=unicode61 "remove_diacritics=2",
              prefix="2,3"
            )
            """
        }
    }
}
