import Foundation
import GRDB

enum DatabaseMigratorFactory {
    static func makeMigrator() -> DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1") { db in
            try db.create(table: "app_meta", ifNotExists: true) { t in
                t.column("key", .text).primaryKey()
                t.column("value", .text).notNull()
            }
        }

        migrator.registerMigration("v2_sessions") { db in
            try db.create(table: "sessions", ifNotExists: true) { t in
                t.column("session_id", .text).primaryKey()
                t.column("created_at_ms", .integer).notNull()
                t.column("last_active_at_ms", .integer).notNull()
                t.column("scene", .text).notNull()
                t.column("flags_json", .text).notNull().defaults(to: "{}")
            }
        }

        return migrator
    }
}
