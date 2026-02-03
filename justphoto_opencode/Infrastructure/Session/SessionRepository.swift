import Foundation
import GRDB

enum SessionRepositoryError: Error {
    case databaseNotReady
}

@MainActor
final class SessionRepository {
    static let shared = SessionRepository()

    private let ttlMs: Int64 = 12 * 60 * 60 * 1000

    private init() {}

    private func queue() throws -> DatabaseQueue {
        guard let q = DatabaseManager.shared.dbQueue else {
            throw SessionRepositoryError.databaseNotReady
        }
        return q
    }

    private static func nowMs(_ now: Date) -> Int64 {
        Int64(now.timeIntervalSince1970 * 1000)
    }

    private func isExpired(lastActiveAtMs: Int64, nowMs: Int64) -> Bool {
        nowMs - lastActiveAtMs > ttlMs
    }

    func currentSessionId() throws -> String? {
        let q = try queue()
        return try q.read { db in
            try String.fetchOne(
                db,
                sql: "SELECT value FROM app_meta WHERE key = ?",
                arguments: ["current_session_id"]
            )
        }
    }

    @discardableResult
    func createNewSession(scene: String, now: Date = .init()) throws -> String {
        let q = try queue()
        let id = UUID().uuidString
        let ms = Self.nowMs(now)

        try q.write { db in
            try db.execute(
                sql: """
                INSERT INTO sessions (session_id, created_at_ms, last_active_at_ms, scene, flags_json)
                VALUES (?, ?, ?, ?, ?)
                """,
                arguments: [id, ms, ms, scene, "{}"]
            )

            try db.execute(
                sql: """
                INSERT INTO app_meta (key, value)
                VALUES (?, ?)
                ON CONFLICT(key) DO UPDATE SET value = excluded.value
                """,
                arguments: ["current_session_id", id]
            )
        }

        return id
    }

    func loadCurrentSession() throws -> (sessionId: String, scene: String, createdAtMs: Int64, lastActiveAtMs: Int64)? {
        let q = try queue()
        guard let id = try currentSessionId() else { return nil }

        return try q.read { db in
            try Row.fetchOne(
                db,
                sql: """
                SELECT session_id, scene, created_at_ms, last_active_at_ms
                FROM sessions
                WHERE session_id = ?
                """,
                arguments: [id]
            ).map { row in
                (
                    sessionId: row["session_id"],
                    scene: row["scene"],
                    createdAtMs: row["created_at_ms"],
                    lastActiveAtMs: row["last_active_at_ms"]
                )
            }
        }
    }

    func touchCurrentSession(now: Date = .init()) throws {
        let q = try queue()
        guard let id = try currentSessionId() else { return }
        let ms = Self.nowMs(now)

        try q.write { db in
            try db.execute(
                sql: "UPDATE sessions SET last_active_at_ms = ? WHERE session_id = ?",
                arguments: [ms, id]
            )
        }
    }

    func clearCurrentSession(deleteData: Bool = true) throws {
        let q = try queue()
        guard let id = try currentSessionId() else { return }

        try q.write { db in
            if deleteData {
                try db.execute(sql: "DELETE FROM session_items WHERE session_id = ?", arguments: [id])
                try db.execute(sql: "DELETE FROM ref_items WHERE session_id = ?", arguments: [id])
                try db.execute(sql: "DELETE FROM sessions WHERE session_id = ?", arguments: [id])
            }
            try db.execute(sql: "DELETE FROM app_meta WHERE key = ?", arguments: ["current_session_id"])
        }
    }

    func currentWorksetCounts() throws -> (sessionItems: Int, refItems: Int)? {
        let q = try queue()
        guard let id = try currentSessionId() else { return nil }

        return try q.read { db in
            let sessionItems = (try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM session_items WHERE session_id = ?",
                arguments: [id]
            )) ?? 0

            let refItems = (try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM ref_items WHERE session_id = ?",
                arguments: [id]
            )) ?? 0

            return (sessionItems: sessionItems, refItems: refItems)
        }
    }

    @discardableResult
    func ensureFreshSession(scene: String, now: Date = .init()) throws -> (sessionId: String, changed: Bool) {
        let nowMs = Self.nowMs(now)
        if let current = try loadCurrentSession() {
            if isExpired(lastActiveAtMs: current.lastActiveAtMs, nowMs: nowMs) {
                let oldId = current.sessionId
                try clearCurrentSession(deleteData: true)
                let newId = try createNewSession(scene: scene, now: now)
                print("SessionTTLExpired: old=\(oldId) new=\(newId)")
                return (sessionId: newId, changed: true)
            }
            return (sessionId: current.sessionId, changed: false)
        }

        let id = try createNewSession(scene: scene, now: now)
        return (sessionId: id, changed: true)
    }

    // MARK: - Debug helpers (for Implementation Plan verification)

    func setCurrentSessionLastActiveMs(_ lastActiveAtMs: Int64) throws {
        let q = try queue()
        guard let id = try currentSessionId() else { return }
        try q.write { db in
            try db.execute(
                sql: "UPDATE sessions SET last_active_at_ms = ? WHERE session_id = ?",
                arguments: [lastActiveAtMs, id]
            )
        }
    }

    func seedWorksetForCurrentSession(now: Date = .init()) throws {
        let q = try queue()
        guard let id = try currentSessionId() else { return }
        let nowMs = Self.nowMs(now)

        try q.write { db in
            try db.execute(
                sql: """
                INSERT INTO session_items (item_id, session_id, shot_seq, created_at_ms, state, liked)
                VALUES (?, ?, ?, ?, ?, ?)
                """,
                arguments: [UUID().uuidString, id, 1, nowMs, "captured_preview", false]
            )

            try db.execute(
                sql: """
                INSERT INTO ref_items (ref_id, session_id, created_at_ms, asset_id, is_selected, target_outputs_json)
                VALUES (?, ?, ?, ?, ?, ?)
                """,
                arguments: [UUID().uuidString, id, nowMs, "debug_asset_id", false, "{}"]
            )
        }
    }
}
