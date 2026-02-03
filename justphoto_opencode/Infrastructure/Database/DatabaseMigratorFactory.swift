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

        migrator.registerMigration("v3_session_items") { db in
            try db.create(table: "session_items", ifNotExists: true) { t in
                t.column("item_id", .text).primaryKey()
                t.column("session_id", .text).notNull().indexed()
                t.column("shot_seq", .integer).notNull()
                t.column("created_at_ms", .integer).notNull()
                t.column("state", .text).notNull()
                t.column("liked", .boolean).notNull().defaults(to: false)
                t.column("asset_id", .text)
                t.column("pending_file_rel_path", .text)
                t.column("thumb_cache_rel_path", .text)
                t.column("last_error_at_ms", .integer)
            }
        }

        migrator.registerMigration("v4_ref_items") { db in
            try db.create(table: "ref_items", ifNotExists: true) { t in
                t.column("ref_id", .text).primaryKey()
                t.column("session_id", .text).notNull().indexed()
                t.column("created_at_ms", .integer).notNull()
                t.column("asset_id", .text).notNull()
                t.column("is_selected", .boolean).notNull().defaults(to: false)
                t.column("target_outputs_json", .text).notNull().defaults(to: "{}")
            }
        }

        migrator.registerMigration("v5_local_stats") { db in
            try db.create(table: "local_stats", ifNotExists: true) { t in
                t.column("key", .text).primaryKey()
                t.column("value", .text).notNull()
                t.column("updated_at_ms", .integer).notNull()
            }
        }

        return migrator
    }
}
