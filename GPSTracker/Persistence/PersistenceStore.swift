import Foundation
import GRDB
import TrackerKit

/// Summary row for the History day list.
struct DaySummary: Identifiable, Hashable, Sendable {
    /// Local-timezone day number (days since 1970-01-01 in local time).
    let day: Int
    let pointCount: Int
    let firstTimestamp: Int32
    let lastTimestamp: Int32

    var id: Int { day }

    var startOfDayDate: Date {
        Date(timeIntervalSince1970: TimeInterval(day * 86_400 - TimeZone.current.secondsFromGMT()))
    }
}

/// Single-file SQLite store (WAL mode via `DatabasePool`), owned by an actor
/// so all buffering and IO is serialized off the main thread.
///
/// Points are buffered in memory and flushed in a single transaction every
/// `flushThreshold` points or `flushIntervalSeconds`, whichever comes first,
/// to keep disk wakeups rare while recording.
actor PersistenceStore {
    static let shared = PersistenceStore()

    static let databaseDirectoryName = "Database"
    static let databaseFileName = "tracker.sqlite"

    private let flushThreshold = 20
    private let flushIntervalSeconds: TimeInterval = 30

    private var pool: DatabasePool?
    private var buffer: [TrackPoint] = []
    private var lastFlushDate = Date()

    // MARK: - Database bootstrap

    private func database() throws -> DatabasePool {
        if let pool { return pool }

        let directory = try Self.databaseDirectory()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
        )
        let databaseURL = directory.appendingPathComponent(Self.databaseFileName)

        // DatabasePool always runs SQLite in WAL journal mode.
        let pool = try DatabasePool(path: databaseURL.path, configuration: Configuration())

        try pool.writeWithoutTransaction { db in
            let version = try Int.fetchOne(db, sql: "PRAGMA user_version") ?? 0
            if version == 0 {
                // Must be set before the first table is created to take effect.
                try db.execute(sql: "PRAGMA auto_vacuum = INCREMENTAL")
            }
            let statements = Schema.migrationStatements(from: version)
            if !statements.isEmpty {
                try db.inTransaction {
                    for statement in statements {
                        try db.execute(sql: statement)
                    }
                    return .commit
                }
                try db.execute(sql: "PRAGMA user_version = \(Schema.currentVersion)")
            }
        }

        applyFileProtection(around: databaseURL)
        applyBackupExclusion(around: databaseURL, excluded: UserDefaults.standard.bool(forKey: SettingsKeys.excludeFromBackup))
        self.pool = pool
        return pool
    }

    static func databaseDirectory() throws -> URL {
        try FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent(databaseDirectoryName, isDirectory: true)
    }

    /// The database plus its WAL sidecar files.
    private func sidecarURLs(of databaseURL: URL) -> [URL] {
        [databaseURL,
         URL(fileURLWithPath: databaseURL.path + "-wal"),
         URL(fileURLWithPath: databaseURL.path + "-shm")]
    }

    private func applyFileProtection(around databaseURL: URL) {
        for url in sidecarURLs(of: databaseURL) where FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: url.path
            )
        }
    }

    private func applyBackupExclusion(around databaseURL: URL, excluded: Bool) {
        for url in sidecarURLs(of: databaseURL) where FileManager.default.fileExists(atPath: url.path) {
            var mutableURL = url
            var values = URLResourceValues()
            values.isExcludedFromBackup = excluded
            try? mutableURL.setResourceValues(values)
        }
    }

    // MARK: - Writing

    /// Buffers one point; flushes when the batch is full or stale.
    func append(_ point: TrackPoint) async {
        buffer.append(point)
        let bufferIsStale = Date().timeIntervalSince(lastFlushDate) >= flushIntervalSeconds
        if buffer.count >= flushThreshold || bufferIsStale {
            await flush()
        }
    }

    /// Writes all buffered points in one transaction. Called on batch limits,
    /// on background transition, and when recording stops.
    func flush() async {
        guard !buffer.isEmpty else { return }
        let points = buffer
        buffer.removeAll(keepingCapacity: true)
        lastFlushDate = Date()
        do {
            let db = try database()
            try await db.write { db in
                let statement = try db.makeStatement(sql: """
                    INSERT INTO point (ts, lat_e7, lon_e7, alt_m, speed_dms, course_deg, hacc_m, activity)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                    """)
                for point in points {
                    try statement.execute(arguments: [
                        point.timestamp, point.latE7, point.lonE7, point.altitude,
                        point.speed, point.course, point.hAccuracy, point.activity.rawValue,
                    ])
                }
            }
        } catch {
            // Put the points back so they are retried on the next flush.
            buffer.insert(contentsOf: points, at: 0)
        }
    }

    // MARK: - Reading

    func points(from: Int32, to: Int32) async throws -> [TrackPoint] {
        await flush()
        let db = try database()
        return try await db.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT ts, lat_e7, lon_e7, alt_m, speed_dms, course_deg, hacc_m, activity
                    FROM point WHERE ts >= ? AND ts < ? ORDER BY ts
                    """,
                arguments: [from, to]
            ).map(Self.trackPoint(from:))
        }
    }

    func simplifiedPoints(day: Int) async throws -> [TrackPoint] {
        let db = try database()
        return try await db.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT ts, lat_e7, lon_e7, alt_m, speed_dms, course_deg, hacc_m, activity
                    FROM simplified_point WHERE day = ? ORDER BY ts
                    """,
                arguments: [day]
            ).map(Self.trackPoint(from:))
        }
    }

    func daySummaries() async throws -> [DaySummary] {
        await flush()
        let db = try database()
        let offset = TimeZone.current.secondsFromGMT()
        return try await db.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT (ts + ?) / 86400 AS day, COUNT(*) AS n, MIN(ts) AS first_ts, MAX(ts) AS last_ts
                    FROM point GROUP BY day ORDER BY day DESC
                    """,
                arguments: [offset]
            ).map { row in
                DaySummary(day: row["day"], pointCount: row["n"], firstTimestamp: row["first_ts"], lastTimestamp: row["last_ts"])
            }
        }
    }

    func totalPointCount() async throws -> Int {
        await flush()
        let db = try database()
        return try await db.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM point") ?? 0
        }
    }

    func databaseSizeBytes() -> Int64 {
        guard let directory = try? Self.databaseDirectory() else { return 0 }
        let databaseURL = directory.appendingPathComponent(Self.databaseFileName)
        return sidecarURLs(of: databaseURL).reduce(Int64(0)) { total, url in
            let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
            let size = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
            return total + size
        }
    }

    private static func trackPoint(from row: Row) -> TrackPoint {
        TrackPoint(
            timestamp: row["ts"], latE7: row["lat_e7"], lonE7: row["lon_e7"],
            altitude: row["alt_m"], speed: row["speed_dms"], course: row["course_deg"],
            hAccuracy: row["hacc_m"],
            activity: ActivityFlag(rawValue: row["activity"]) ?? .unknown
        )
    }

    // MARK: - Maintenance

    /// Deletes raw and simplified points older than the retention window.
    func deletePoints(olderThanDays days: Int) async throws {
        await flush()
        let cutoff = Int32(clamping: Int(Date().timeIntervalSince1970) - days * 86_400)
        let cutoffDay = (Int(cutoff) + TimeZone.current.secondsFromGMT()) / 86_400
        let db = try database()
        try await db.write { db in
            try db.execute(sql: "DELETE FROM point WHERE ts < ?", arguments: [cutoff])
            try db.execute(sql: "DELETE FROM simplified_point WHERE day < ?", arguments: [cutoffDay])
        }
        try await db.writeWithoutTransaction { db in
            try db.execute(sql: "PRAGMA incremental_vacuum")
        }
    }

    func deleteAllData() async throws {
        buffer.removeAll()
        let db = try database()
        try await db.write { db in
            try db.execute(sql: "DELETE FROM point")
            try db.execute(sql: "DELETE FROM simplified_point")
        }
        try await db.writeWithoutTransaction { db in
            try db.execute(sql: "PRAGMA incremental_vacuum")
        }
    }

    /// Background Douglas-Peucker pass: simplifies every *completed* local day
    /// that has raw points but no simplified track yet. Raw data is never touched.
    func simplifyCompletedDays(toleranceMeters: Double = 15) async throws {
        await flush()
        let db = try database()
        let offset = TimeZone.current.secondsFromGMT()
        let today = (Int(Date().timeIntervalSince1970) + offset) / 86_400

        let pendingDays: [Int] = try await db.read { db in
            try Int.fetchAll(
                db,
                sql: """
                    SELECT DISTINCT (ts + ?) / 86400 AS day FROM point
                    WHERE day < ? AND day NOT IN (SELECT DISTINCT day FROM simplified_point)
                    ORDER BY day
                    """,
                arguments: [offset, today]
            )
        }

        for day in pendingDays {
            let from = Int32(clamping: day * 86_400 - offset)
            let to = Int32(clamping: (day + 1) * 86_400 - offset)
            let rawPoints = try await points(from: from, to: to)
            guard !rawPoints.isEmpty else { continue }
            let simplified = DouglasPeucker.simplify(rawPoints, toleranceMeters: toleranceMeters)
            try await db.write { db in
                let statement = try db.makeStatement(sql: """
                    INSERT INTO simplified_point (day, ts, lat_e7, lon_e7, alt_m, speed_dms, course_deg, hacc_m, activity)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """)
                for point in simplified {
                    try statement.execute(arguments: [
                        day, point.timestamp, point.latE7, point.lonE7, point.altitude,
                        point.speed, point.course, point.hAccuracy, point.activity.rawValue,
                    ])
                }
            }
        }
    }

    /// Applies the "exclude from iCloud backup" setting to the database files.
    func setExcludedFromBackup(_ excluded: Bool) {
        guard let directory = try? Self.databaseDirectory() else { return }
        applyBackupExclusion(around: directory.appendingPathComponent(Self.databaseFileName), excluded: excluded)
    }
}
