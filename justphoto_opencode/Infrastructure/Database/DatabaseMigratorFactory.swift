import Foundation
import GRDB

enum DatabaseMigratorFactory {
    static func makeMigrator() -> DatabaseMigrator {
        var migrator = DatabaseMigrator()

        // Development-mode: structural changes are allowed to wipe local DB.
        migrator.eraseDatabaseOnSchemaChange = true

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

        migrator.registerMigration("v6_album_retry") { db in
            // M4.27: automatic retry backoff metadata for album_add_failed.
            try db.alter(table: "session_items") { t in
                t.add(column: "album_retry_count", .integer).notNull().defaults(to: 0)
                t.add(column: "album_retry_last_at_ms", .integer)
                t.add(column: "album_retry_next_at_ms", .integer)
            }
        }

        migrator.registerMigration("v7_split_item_states") { db in
            // M4.22+ structural fix: split `state` responsibilities.
            // - `state` becomes core lifecycle: captured_preview/writing/write_failed/finalized
            // - `thumbnail_state` tracks thumbnail status: ready/failed
            // - `album_state` tracks album archiving: queued/success/failed

            try db.alter(table: "session_items") { t in
                t.add(column: "thumbnail_state", .text)
                t.add(column: "album_state", .text)
            }

            // Migrate from legacy overloaded `state` values.
            try db.execute(
                sql: """
                UPDATE session_items
                SET thumbnail_state = CASE state
                    WHEN 'thumb_ready' THEN 'ready'
                    WHEN 'thumb_failed' THEN 'failed'
                    ELSE thumbnail_state
                END
                """
            )

            try db.execute(
                sql: """
                UPDATE session_items
                SET album_state = CASE state
                    WHEN 'album_add_success' THEN 'success'
                    WHEN 'album_add_failed' THEN 'failed'
                    ELSE album_state
                END
                """
            )

            // Normalize core lifecycle.
            try db.execute(
                sql: """
                UPDATE session_items
                SET state = CASE
                    WHEN state IN ('write_success', 'thumb_ready', 'thumb_failed', 'album_add_success', 'album_add_failed') THEN 'finalized'
                    ELSE state
                END
                """
            )

            // If already finalized and has asset id, default album_state to queued.
            try db.execute(
                sql: """
                UPDATE session_items
                SET album_state = 'queued'
                WHERE state = 'finalized'
                  AND asset_id IS NOT NULL
                  AND asset_id != ''
                  AND album_state IS NULL
                """
            )
        }

        return migrator
    }
}
