import Foundation
import GRDB

@MainActor
final class DatabaseManager {
    static let shared = DatabaseManager()

    private(set) var dbQueue: DatabaseQueue?

    private init() {}

    @discardableResult
    func start() throws -> (path: String, existedBefore: Bool, existsAfter: Bool) {
        if let dbQueue {
            let url = try DatabasePaths.databaseFileURL()
            return (
                path: url.path,
                existedBefore: FileManager.default.fileExists(atPath: url.path),
                existsAfter: true
            )
        }

        let url = try DatabasePaths.databaseFileURL()
        let existedBefore = FileManager.default.fileExists(atPath: url.path)

        let queue = try DatabaseQueueFactory.openDatabaseQueue(at: url)

        // Force at least one database access so the sqlite file is created on first launch.
        try queue.read { db in
            _ = try Int.fetchOne(db, sql: "SELECT 1")
        }

        self.dbQueue = queue
        let existsAfter = FileManager.default.fileExists(atPath: url.path)
        return (path: url.path, existedBefore: existedBefore, existsAfter: existsAfter)
    }
}
