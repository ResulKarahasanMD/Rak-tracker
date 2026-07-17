/// Versioned SQL schema shared by the app's GRDB store and the unit tests
/// (which run the same statements against a plain SQLite handle, including
/// on Linux). The schema version is tracked via `PRAGMA user_version`.
public enum Schema {
    public struct Migration: Sendable {
        public let version: Int
        public let statements: [String]

        public init(version: Int, statements: [String]) {
            self.version = version
            self.statements = statements
        }
    }

    /// All migrations, ordered by version, starting at 1.
    ///
    /// `id INTEGER PRIMARY KEY` aliases SQLite's rowid, so it costs no extra
    /// payload bytes. Small integers are stored in SQLite's variable-width
    /// record format, which keeps a typical row near the 21-byte field payload.
    public static let migrations: [Migration] = [
        Migration(version: 1, statements: [
            """
            CREATE TABLE point (
                id INTEGER PRIMARY KEY,
                ts INTEGER NOT NULL,
                lat_e7 INTEGER NOT NULL,
                lon_e7 INTEGER NOT NULL,
                alt_m INTEGER NOT NULL DEFAULT 0,
                speed_dms INTEGER NOT NULL DEFAULT -1,
                course_deg INTEGER NOT NULL DEFAULT -1,
                hacc_m INTEGER NOT NULL DEFAULT -1,
                activity INTEGER NOT NULL DEFAULT 0
            )
            """,
            "CREATE INDEX idx_point_ts ON point(ts)",
            """
            CREATE TABLE simplified_point (
                id INTEGER PRIMARY KEY,
                day INTEGER NOT NULL,
                ts INTEGER NOT NULL,
                lat_e7 INTEGER NOT NULL,
                lon_e7 INTEGER NOT NULL,
                alt_m INTEGER NOT NULL DEFAULT 0,
                speed_dms INTEGER NOT NULL DEFAULT -1,
                course_deg INTEGER NOT NULL DEFAULT -1,
                hacc_m INTEGER NOT NULL DEFAULT -1,
                activity INTEGER NOT NULL DEFAULT 0
            )
            """,
            "CREATE INDEX idx_simplified_point_day ON simplified_point(day, ts)",
        ]),
    ]

    /// The version an up-to-date database reports in `PRAGMA user_version`.
    public static var currentVersion: Int { migrations.last?.version ?? 0 }

    /// Statements needed to bring a database at `version` up to date.
    public static func migrationStatements(from version: Int) -> [String] {
        migrations.filter { $0.version > version }.flatMap(\.statements)
    }
}
