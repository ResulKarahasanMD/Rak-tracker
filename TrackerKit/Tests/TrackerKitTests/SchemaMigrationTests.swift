import Testing
import CSQLite
@testable import TrackerKit

/// Minimal SQLite handle for verifying that the SQL shipped in `Schema`
/// actually runs against a real SQLite library (works on Linux and Darwin).
private final class TestDatabase {
    let handle: OpaquePointer

    init() throws {
        var db: OpaquePointer?
        guard sqlite3_open(":memory:", &db) == SQLITE_OK, let db else {
            throw TestDatabaseError(message: "cannot open in-memory database")
        }
        handle = db
    }

    deinit { sqlite3_close(handle) }

    func execute(_ sql: String) throws {
        var errorMessage: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(handle, sql, nil, nil, &errorMessage) == SQLITE_OK else {
            let message = errorMessage.map { String(cString: $0) } ?? "unknown"
            sqlite3_free(errorMessage)
            throw TestDatabaseError(message: "\(message) — while executing: \(sql)")
        }
    }

    func queryStrings(_ sql: String) throws -> [String] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
            throw TestDatabaseError(message: String(cString: sqlite3_errmsg(handle)))
        }
        defer { sqlite3_finalize(statement) }
        var rows: [String] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let text = sqlite3_column_text(statement, 0) {
                rows.append(String(cString: text))
            }
        }
        return rows
    }

    func queryInt(_ sql: String) throws -> Int {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
            throw TestDatabaseError(message: String(cString: sqlite3_errmsg(handle)))
        }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw TestDatabaseError(message: "no row for: \(sql)")
        }
        return Int(sqlite3_column_int64(statement, 0))
    }

    func columnNames(of table: String) throws -> [String] {
        try queryStrings("SELECT name FROM pragma_table_info('\(table)') ORDER BY cid")
    }

    /// Applies all schema migrations newer than the schema's current recorded version.
    func migrateToLatest() throws {
        let version = try queryInt("PRAGMA user_version")
        for statement in Schema.migrationStatements(from: version) {
            try execute(statement)
        }
        try execute("PRAGMA user_version = \(Schema.currentVersion)")
    }
}

private struct TestDatabaseError: Error, CustomStringConvertible {
    let message: String
    var description: String { message }
}

@Suite("Schema migrations")
struct SchemaMigrationTests {
    @Test func migratesEmptyDatabaseToLatest() throws {
        let db = try TestDatabase()
        try db.migrateToLatest()

        let tables = try db.queryStrings(
            "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' ORDER BY name"
        )
        #expect(tables == ["point", "simplified_point"])
        #expect(try db.queryInt("PRAGMA user_version") == Schema.currentVersion)
    }

    @Test func pointTableHasCompactColumnLayout() throws {
        let db = try TestDatabase()
        try db.migrateToLatest()
        let columns = try db.columnNames(of: "point")
        #expect(columns == ["id", "ts", "lat_e7", "lon_e7", "alt_m", "speed_dms", "course_deg", "hacc_m", "activity"])
    }

    @Test func simplifiedPointTableHasDayColumn() throws {
        let db = try TestDatabase()
        try db.migrateToLatest()
        let columns = try db.columnNames(of: "simplified_point")
        #expect(columns == ["id", "day", "ts", "lat_e7", "lon_e7", "alt_m", "speed_dms", "course_deg", "hacc_m", "activity"])
    }

    @Test func timestampIndexesExist() throws {
        let db = try TestDatabase()
        try db.migrateToLatest()
        let indexes = try db.queryStrings(
            "SELECT name FROM sqlite_master WHERE type = 'index' AND name NOT LIKE 'sqlite_%' ORDER BY name"
        )
        #expect(indexes.contains("idx_point_ts"))
        #expect(indexes.contains("idx_simplified_point_day"))
    }

    @Test func stepwiseMigrationMatchesDirectMigration() throws {
        // Apply migrations one version at a time…
        let stepwise = try TestDatabase()
        for migration in Schema.migrations {
            for statement in migration.statements {
                try stepwise.execute(statement)
            }
            try stepwise.execute("PRAGMA user_version = \(migration.version)")
        }
        // …and all at once. Resulting schemas must be identical.
        let direct = try TestDatabase()
        try direct.migrateToLatest()

        let schemaSQL = "SELECT COALESCE(sql, '') FROM sqlite_master WHERE name NOT LIKE 'sqlite_%' ORDER BY name"
        #expect(try stepwise.queryStrings(schemaSQL) == (try direct.queryStrings(schemaSQL)))
        #expect(try stepwise.queryInt("PRAGMA user_version") == Schema.currentVersion)
    }

    @Test func migratingFromLatestIsANoOp() {
        #expect(Schema.migrationStatements(from: Schema.currentVersion).isEmpty)
    }

    @Test func migrationVersionsAreStrictlyIncreasingFromOne() {
        #expect(Schema.migrations.map(\.version) == Array(1...Schema.currentVersion))
    }

    @Test func insertAndReadBackRoundTrip() throws {
        let db = try TestDatabase()
        try db.migrateToLatest()
        try db.execute("""
            INSERT INTO point (ts, lat_e7, lon_e7, alt_m, speed_dms, course_deg, hacc_m, activity)
            VALUES (1705314600, 525200066, 134049540, 34, 13, 275, 5, 2)
            """)
        #expect(try db.queryInt("SELECT COUNT(*) FROM point") == 1)
        #expect(try db.queryInt("SELECT lat_e7 FROM point LIMIT 1") == 525_200_066)
    }

    @Test func storageStaysUnderFiftyMegabytesPerYear() throws {
        // 1 point / 30 s for 8 h of movement per day, 365 days ≈ 350k points.
        // Verify actual on-disk cost per row (in-memory page accounting matches
        // file layout) stays comfortably within the 50 MB / year budget.
        let db = try TestDatabase()
        try db.migrateToLatest()
        try db.execute("BEGIN")
        var statement: OpaquePointer?
        let sql = "INSERT INTO point (ts, lat_e7, lon_e7, alt_m, speed_dms, course_deg, hacc_m, activity) VALUES (?,?,?,?,?,?,?,?)"
        #expect(sqlite3_prepare_v2(db.handle, sql, -1, &statement, nil) == SQLITE_OK)
        defer { sqlite3_finalize(statement) }
        let count = 350_000
        for i in 0..<count {
            sqlite3_bind_int64(statement, 1, sqlite3_int64(1_700_000_000 + i * 30))
            sqlite3_bind_int64(statement, 2, 525_200_066 + sqlite3_int64(i % 1000))
            sqlite3_bind_int64(statement, 3, 134_049_540 + sqlite3_int64(i % 1000))
            sqlite3_bind_int(statement, 4, 34)
            sqlite3_bind_int(statement, 5, 13)
            sqlite3_bind_int(statement, 6, 275)
            sqlite3_bind_int(statement, 7, 5)
            sqlite3_bind_int(statement, 8, 2)
            #expect(sqlite3_step(statement) == SQLITE_DONE)
            sqlite3_reset(statement)
        }
        try db.execute("COMMIT")
        let pageSize = try db.queryInt("PRAGMA page_size")
        let pageCount = try db.queryInt("PRAGMA page_count")
        let totalBytes = pageSize * pageCount
        #expect(totalBytes < 50 * 1024 * 1024, "one year of raw points used \(totalBytes) bytes")
        // Sanity: bytes per point should be near the ~20-byte design target
        // (SQLite adds per-row and per-page overhead on top of the payload).
        #expect(totalBytes / count < 60)
    }
}
