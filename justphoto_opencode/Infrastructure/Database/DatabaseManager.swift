import Foundation
import GRDB

final class DatabaseManager {
    static let shared = DatabaseManager()

    struct StartMetrics: Sendable {
        let startedAt: Date
        let durationMs: Int
        let wasMainThread: Bool
        let path: String
        let existedBefore: Bool
        let existsAfter: Bool
        let newMigrations: [String]
    }

    private let startLock = NSLock()
    private let stateLock = NSLock()
    private var _dbQueue: DatabaseQueue?
    private var _lastStartMetrics: StartMetrics?

    var dbQueue: DatabaseQueue? {
        stateLock.lock()
        defer { stateLock.unlock() }
        return _dbQueue
    }

    var lastStartMetrics: StartMetrics? {
        stateLock.lock()
        defer { stateLock.unlock() }
        return _lastStartMetrics
    }

    private init() {}

    private func appliedMigrations(_ queue: DatabaseQueue) throws -> Set<String> {
        try queue.read { db in
            let exists = try db.tableExists("grdb_migrations")
            guard exists else { return [] }
            let rows = try Row.fetchAll(db, sql: "SELECT identifier FROM grdb_migrations")
            return Set(rows.compactMap { $0["identifier"] as String? })
        }
    }

    @discardableResult
    func start() throws -> (path: String, existedBefore: Bool, existsAfter: Bool, newMigrations: [String]) {
        startLock.lock()
        defer { startLock.unlock() }

        if dbQueue != nil {
            let url = try DatabasePaths.databaseFileURL()
            return (
                path: url.path,
                existedBefore: FileManager.default.fileExists(atPath: url.path),
                existsAfter: true,
                newMigrations: []
            )
        }

        let startedAt = Date()
        let wasMainThread = Thread.isMainThread

        let url = try DatabasePaths.databaseFileURL()
        let existedBefore = FileManager.default.fileExists(atPath: url.path)

        let queue = try DatabaseQueueFactory.openDatabaseQueue(at: url)

        // Force at least one database access so the sqlite file is created on first launch.
        try queue.read { db in
            _ = try Int.fetchOne(db, sql: "SELECT 1")
        }

        let before = try appliedMigrations(queue)
        let migrator = DatabaseMigratorFactory.makeMigrator()
        try migrator.migrate(queue)
        let after = try appliedMigrations(queue)
        let newMigrations = Array(after.subtracting(before)).sorted()

        stateLock.lock()
        self._dbQueue = queue
        self._lastStartMetrics = StartMetrics(
            startedAt: startedAt,
            durationMs: Int((Date().timeIntervalSince(startedAt) * 1000).rounded()),
            wasMainThread: wasMainThread,
            path: url.path,
            existedBefore: existedBefore,
            existsAfter: FileManager.default.fileExists(atPath: url.path),
            newMigrations: newMigrations
        )
        stateLock.unlock()
        let existsAfter = FileManager.default.fileExists(atPath: url.path)
        return (
            path: url.path,
            existedBefore: existedBefore,
            existsAfter: existsAfter,
            newMigrations: newMigrations
        )
    }

    func flush(reason: String) {
        guard let q = dbQueue else { return }
        do {
            try q.write { db in
                // Ensure any pending WAL frames are checkpointed to the main db file.
                // This is the "flush" used for M1.19 (backgrounding, write_failed).
                try db.execute(sql: "PRAGMA wal_checkpoint(TRUNCATE)")
            }
            JPDebugPrint("DBFlushed: \(reason)")
        } catch {
            JPDebugPrint("DBFlushFAILED: \(reason) error=\(error)")
        }
    }
}
