import Foundation
import GRDB

enum DatabaseQueueFactory {
    /// NOTE: Opening a DatabaseQueue can create the database file if missing.
    /// M1.11 will decide when/where the DB is created and opened.
    static func openDatabaseQueue(at url: URL) throws -> DatabaseQueue {
        var config = Configuration()
        config.label = "JustPhoto"
        return try DatabaseQueue(path: url.path, configuration: config)
    }
}
