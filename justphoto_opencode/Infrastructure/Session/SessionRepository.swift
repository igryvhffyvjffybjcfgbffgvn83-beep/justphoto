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

    private func nextShotSeq(db: Database, sessionId: String) throws -> Int {
        let last = try Int.fetchOne(
            db,
            sql: "SELECT MAX(shot_seq) FROM session_items WHERE session_id = ?",
            arguments: [sessionId]
        )
        return (last ?? 0) + 1
    }

    struct SessionItemSummary: Sendable, Equatable {
        let itemId: String
        let sessionId: String
        let shotSeq: Int
        let createdAtMs: Int64
        let state: SessionItemState
        let liked: Bool
        let assetId: String?
        let pendingFileRelPath: String?
        let thumbCacheRelPath: String?
        let thumbnailState: ThumbnailState?
        let albumState: AlbumState?
    }

    struct CleanupResult: Sendable, Equatable {
        let itemId: String
        let deletedRowCount: Int
        let pendingFileRelPath: String?
        let thumbCacheRelPath: String?
        let pendingDeleted: Bool
        let thumbDeleted: Bool
    }

    struct AlbumAddRetryCandidate: Sendable, Equatable {
        let itemId: String
        let sessionId: String
        let assetId: String
        let coreState: SessionItemState
        let albumState: AlbumState
        let retryCount: Int
        let nextAtMs: Int64?
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

        var refs: [(pending: String?, thumb: String?)] = []

        try q.write { db in
            if deleteData {
                let rows = try Row.fetchAll(
                    db,
                    sql: """
                    SELECT pending_file_rel_path, thumb_cache_rel_path
                    FROM session_items
                    WHERE session_id = ?
                    """,
                    arguments: [id]
                )
                refs = rows.map { row in
                    (pending: row["pending_file_rel_path"], thumb: row["thumb_cache_rel_path"])
                }

                try db.execute(sql: "DELETE FROM session_items WHERE session_id = ?", arguments: [id])
                try db.execute(sql: "DELETE FROM ref_items WHERE session_id = ?", arguments: [id])
                try db.execute(sql: "DELETE FROM sessions WHERE session_id = ?", arguments: [id])
            }
            try db.execute(sql: "DELETE FROM app_meta WHERE key = ?", arguments: ["current_session_id"])
        }

        // Best-effort file cleanup.
        if deleteData {
            for r in refs {
                if let rel = r.pending {
                    _ = try? PendingFileStore.shared.delete(relativePath: rel)
                }
                if let rel = r.thumb {
                    _ = try? ThumbCacheStore.shared.delete(relativePath: rel)
                }
            }
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

    func currentWorksetCounter() throws -> WorksetCounter.Counts? {
        let q = try queue()
        guard let id = try currentSessionId() else { return nil }

        return try q.read { db in
            try WorksetCounter.fetch(db: db, sessionId: id)
        }
    }

    // MARK: - Session flags (for Prompt gates)

    private func decodeFlagsJSON(_ json: String) -> [String: Bool] {
        guard let data = json.data(using: .utf8) else { return [:] }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        var out: [String: Bool] = [:]
        for (k, v) in obj {
            if let b = v as? Bool {
                out[k] = b
            } else if let n = v as? NSNumber {
                out[k] = n.boolValue
            }
        }
        return out
}

    private func encodeFlagsJSON(_ flags: [String: Bool]) -> String {
        let obj: [String: Any] = flags
        guard let data = try? JSONSerialization.data(withJSONObject: obj, options: []) else { return "{}" }
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    func sessionFlagBool(_ key: String) throws -> Bool {
        let q = try queue()
        guard let sessionId = try currentSessionId() else { return false }
        return try q.read { db in
            let json = (try String.fetchOne(
                db,
                sql: "SELECT flags_json FROM sessions WHERE session_id = ?",
                arguments: [sessionId]
            )) ?? "{}"
            let flags = decodeFlagsJSON(json)
            return flags[key] ?? false
        }
    }

    func setSessionFlagBool(_ key: String, value: Bool) throws {
        let q = try queue()
        guard let sessionId = try currentSessionId() else { return }
        try q.write { db in
            let json = (try String.fetchOne(
                db,
                sql: "SELECT flags_json FROM sessions WHERE session_id = ?",
                arguments: [sessionId]
            )) ?? "{}"
            var flags = decodeFlagsJSON(json)
            flags[key] = value
            let updated = encodeFlagsJSON(flags)
            try db.execute(
                sql: "UPDATE sessions SET flags_json = ? WHERE session_id = ?",
                arguments: [updated, sessionId]
            )
        }
    }

    // MARK: - Session item bulk actions

    @discardableResult
    func clearUnlikedItemsForCurrentSession(now: Date = .init(), flush: Bool = true) throws -> Int {
        let q = try queue()
        guard let sessionId = try currentSessionId() else { return 0 }

        var deleted = 0
        var refs: [(pending: String?, thumb: String?)] = []
        try q.write { db in
            // PRD M4.4: "clear unliked" should not silently drop unsaved/in-flight items.
            // Only remove items that are both unliked and not in critical states.
            let rows = try Row.fetchAll(
                db,
                sql: """
                SELECT pending_file_rel_path, thumb_cache_rel_path
                FROM session_items
                WHERE session_id = ?
                  AND liked = 0
                  AND state NOT IN (?, ?, ?)
                """,
                arguments: [
                    sessionId,
                    SessionItemState.write_failed.rawValue,
                    SessionItemState.writing.rawValue,
                    SessionItemState.captured_preview.rawValue,
                ]
            )
            refs = rows.map { row in
                (pending: row["pending_file_rel_path"], thumb: row["thumb_cache_rel_path"])
            }

            try db.execute(
                sql: """
                DELETE FROM session_items
                WHERE session_id = ?
                  AND liked = 0
                  AND state NOT IN (?, ?, ?)
                """,
                arguments: [
                    sessionId,
                    SessionItemState.write_failed.rawValue,
                    SessionItemState.writing.rawValue,
                    SessionItemState.captured_preview.rawValue,
                ]
            )
            deleted = db.changesCount

            let nowMs = Self.nowMs(now)
            try db.execute(
                sql: "UPDATE sessions SET last_active_at_ms = ? WHERE session_id = ?",
                arguments: [nowMs, sessionId]
            )
        }

        if flush {
            DatabaseManager.shared.flush(reason: "clear_unliked")
        }

        // Best-effort file cleanup for removed items.
        if deleted > 0 {
            for r in refs {
                if let rel = r.pending {
                    _ = try? PendingFileStore.shared.delete(relativePath: rel)
                }
                if let rel = r.thumb {
                    _ = try? ThumbCacheStore.shared.delete(relativePath: rel)
                }
            }
        }
        return deleted
    }

    @discardableResult
    func setLikedForLatestItemsForCurrentSession(count: Int, liked: Bool) throws -> Int {
        let q = try queue()
        guard let sessionId = try currentSessionId() else { return 0 }

        let n = max(0, count)
        guard n > 0 else { return 0 }

        var updated = 0
        try q.write { db in
            try db.execute(
                sql: """
                UPDATE session_items
                SET liked = ?
                WHERE item_id IN (
                    SELECT item_id
                    FROM session_items
                    WHERE session_id = ?
                    ORDER BY created_at_ms DESC, shot_seq DESC
                    LIMIT ?
                )
                """,
                arguments: [liked ? 1 : 0, sessionId, n]
            )
            updated = db.changesCount
        }
        return updated
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
                arguments: [UUID().uuidString, id, 1, nowMs, SessionItemState.captured_preview.rawValue, false]
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

    @discardableResult
    func insertWorksetItemsForCurrentSession(
        count: Int,
        state: SessionItemState = .finalized,
        now: Date = .init(),
        flush: Bool = true
    ) throws -> Int {
        let q = try queue()
        guard let id = try currentSessionId() else {
            throw SessionRepositoryError.databaseNotReady
        }

        let nowMs = Self.nowMs(now)
        let n = max(0, count)
        guard n > 0 else { return 0 }

        try q.write { db in
            let startSeq = (try Int.fetchOne(
                db,
                sql: "SELECT MAX(shot_seq) FROM session_items WHERE session_id = ?",
                arguments: [id]
            )) ?? 0

            for i in 0..<n {
                let itemId = UUID().uuidString
                let shotSeq = startSeq + i + 1
                try db.execute(
                    sql: """
                    INSERT INTO session_items (item_id, session_id, shot_seq, created_at_ms, state, liked)
                    VALUES (?, ?, ?, ?, ?, ?)
                    """,
                    arguments: [itemId, id, shotSeq, nowMs, state.rawValue, false]
                )
            }
        }

        if flush {
            DatabaseManager.shared.flush(reason: "debug_insert_workset_items")
        }
        return n
    }

    @discardableResult
    func insertWriteFailedItemAndFlush(now: Date = .init()) throws -> String {
        let q = try queue()
        guard let id = try currentSessionId() else {
            throw SessionRepositoryError.databaseNotReady
        }
        let nowMs = Self.nowMs(now)
        let itemId = UUID().uuidString

        try q.write { db in
            let shotSeq = try nextShotSeq(db: db, sessionId: id)
            try db.execute(
                sql: """
                INSERT INTO session_items (item_id, session_id, shot_seq, created_at_ms, state, liked, last_error_at_ms)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                """,
                arguments: [itemId, id, shotSeq, nowMs, SessionItemState.write_failed.rawValue, false, nowMs]
            )
        }

        // Debug helper: ensure synthetic write_failed items are retryable.
        #if DEBUG
        do {
            let rel = PendingFileStore.shared.makeRelativePath(itemId: itemId, fileExtension: "png")
            let b64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMB/6X9nN8AAAAASUVORK5CYII="
            let data = Data(base64Encoded: b64) ?? Data([0x89, 0x50, 0x4E, 0x47])
            _ = try PendingFileStore.shared.writeAtomic(data: data, toRelativePath: rel)
            try updatePendingFileRelPath(itemId: itemId, relPath: rel, flush: false)
            print("WriteFailedDebugPendingCreated: item_id=\(itemId) rel=\(rel) bytes=\(data.count)")
        } catch {
            print("WriteFailedDebugPendingCreateFAILED: \(error)")
        }
        #endif

        DatabaseManager.shared.flush(reason: SessionItemState.write_failed.rawValue)
        return itemId
    }

    func countWriteFailedItems() throws -> Int {
        let q = try queue()
        guard let id = try currentSessionId() else { return 0 }
        return try q.read { db in
            (try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM session_items WHERE session_id = ? AND state = ?",
                arguments: [id, SessionItemState.write_failed.rawValue]
            )) ?? 0
        }
    }

    func countAlbumAddFailedItems() throws -> Int {
        let q = try queue()
        guard let sessionId = try currentSessionId() else { return 0 }
        return try q.read { db in
            try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM session_items WHERE session_id = ? AND album_state = ?",
                arguments: [sessionId, AlbumState.failed.rawValue]
            ) ?? 0
        }
    }

    func albumAddFailedAutoRetryCandidates(maxAttempts: Int) throws -> [AlbumAddRetryCandidate] {
        let q = try queue()
        guard let sessionId = try currentSessionId() else { return [] }
        let maxN = max(1, maxAttempts)

        return try q.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                SELECT item_id, session_id, asset_id, state, album_state, album_retry_count, album_retry_next_at_ms, created_at_ms
                FROM session_items
                WHERE session_id = ?
                  AND album_state = ?
                  AND state = ?
                  AND asset_id IS NOT NULL
                  AND asset_id != ''
                  AND album_retry_count < ?
                ORDER BY created_at_ms DESC, shot_seq DESC
                """,
                arguments: [sessionId, AlbumState.failed.rawValue, SessionItemState.finalized.rawValue, maxN]
            )

            return rows.compactMap { row in
                let coreRaw: String = row["state"]
                guard let coreState = SessionItemState(rawValue: coreRaw) else { return nil }
                let albumRaw: String? = row["album_state"]
                guard let albumState = albumRaw.flatMap({ AlbumState(rawValue: $0) }) else { return nil }
                return AlbumAddRetryCandidate(
                    itemId: row["item_id"],
                    sessionId: row["session_id"],
                    assetId: row["asset_id"],
                    coreState: coreState,
                    albumState: albumState,
                    retryCount: row["album_retry_count"],
                    nextAtMs: row["album_retry_next_at_ms"]
                )
            }
        }
    }

    func albumAddRetryCandidate(itemId: String) throws -> AlbumAddRetryCandidate? {
        let q = try queue()
        return try q.read { db in
            let row = try Row.fetchOne(
                db,
                sql: """
                SELECT item_id, session_id, asset_id, state, album_state, album_retry_count, album_retry_next_at_ms
                FROM session_items
                WHERE item_id = ?
                LIMIT 1
                """,
                arguments: [itemId]
            )
            guard let row else { return nil }
            let coreRaw: String = row["state"]
            guard let coreState = SessionItemState(rawValue: coreRaw) else { return nil }
            let albumRaw: String? = row["album_state"]
            guard let albumState = albumRaw.flatMap({ AlbumState(rawValue: $0) }) else { return nil }
            let asset: String = row["asset_id"]
            return AlbumAddRetryCandidate(
                itemId: row["item_id"],
                sessionId: row["session_id"],
                assetId: asset,
                coreState: coreState,
                albumState: albumState,
                retryCount: row["album_retry_count"],
                nextAtMs: row["album_retry_next_at_ms"]
            )
        }
    }

    func scheduleAlbumAutoRetryIfNeeded(itemId: String, now: Date, delayMs: Int64) throws -> Int64 {
        let q = try queue()
        let nowMs = Self.nowMs(now)
        let nextMs = nowMs + max(0, delayMs)

        try q.write { db in
            // Only set next_at if it is currently NULL.
            try db.execute(
                sql: """
                UPDATE session_items
                SET album_retry_next_at_ms = COALESCE(album_retry_next_at_ms, ?)
                WHERE item_id = ?
                """,
                arguments: [nextMs, itemId]
            )
        }
        DatabaseManager.shared.flush(reason: "album_retry_schedule")
        return nextMs
    }

    func beginAlbumAutoRetryAttempt(itemId: String, now: Date) throws {
        let q = try queue()
        let nowMs = Self.nowMs(now)
        try q.write { db in
            try db.execute(
                sql: """
                UPDATE session_items
                SET album_retry_last_at_ms = ?,
                    album_retry_next_at_ms = NULL
                WHERE item_id = ?
                """,
                arguments: [nowMs, itemId]
            )
        }
        DatabaseManager.shared.flush(reason: "album_retry_begin")
    }

    func bumpAlbumAutoRetryFailure(itemId: String, now: Date, nextDelayMs: Int64?) throws {
        let q = try queue()
        let nowMs = Self.nowMs(now)
        let nextMs: Int64? = nextDelayMs.map { nowMs + $0 }

        try q.write { db in
            try db.execute(
                sql: """
                UPDATE session_items
                SET album_retry_count = COALESCE(album_retry_count, 0) + 1,
                    album_retry_last_at_ms = ?,
                    album_retry_next_at_ms = ?
                WHERE item_id = ?
                """,
                arguments: [nowMs, nextMs, itemId]
            )
        }
        DatabaseManager.shared.flush(reason: "album_retry_bump")
    }

    func markAlbumAddSuccess(itemId: String, now: Date = .init()) throws {
        let q = try queue()
        let nowMs = Self.nowMs(now)
        try q.write { db in
            try db.execute(
                sql: """
                UPDATE session_items
                SET album_state = ?,
                    album_retry_next_at_ms = NULL
                WHERE item_id = ?
                """,
                arguments: [AlbumState.success.rawValue, itemId]
            )
            try db.execute(
                sql: "UPDATE sessions SET last_active_at_ms = ? WHERE session_id = (SELECT session_id FROM session_items WHERE item_id = ?)",
                arguments: [nowMs, itemId]
            )
        }

        print("AlbumStateUpdated: item_id=\(itemId) album_state=\(AlbumState.success.rawValue)")
        DatabaseManager.shared.flush(reason: "album_add_success")
    }

    func albumAddFailedItemsForCurrentSession(limit: Int = 200) throws -> [SessionItemSummary] {
        let q = try queue()
        guard let sessionId = try currentSessionId() else { return [] }

        let n = max(1, min(500, limit))
        return try q.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                SELECT item_id, session_id, shot_seq, created_at_ms, state, liked,
                       asset_id, pending_file_rel_path, thumb_cache_rel_path,
                       thumbnail_state, album_state
                FROM session_items
                WHERE session_id = ?
                  AND album_state = ?
                ORDER BY created_at_ms DESC, shot_seq DESC
                LIMIT ?
                """,
                arguments: [sessionId, AlbumState.failed.rawValue, n]
            )

            return rows.compactMap { row in
                let raw: String = row["state"]
                guard let state = SessionItemState(rawValue: raw) else { return nil }

                let thumbRaw: String? = row["thumbnail_state"]
                let albumRaw: String? = row["album_state"]
                let thumbState = thumbRaw.flatMap { ThumbnailState(rawValue: $0) }
                let albumState = albumRaw.flatMap { AlbumState(rawValue: $0) }

                return SessionItemSummary(
                    itemId: row["item_id"],
                    sessionId: row["session_id"],
                    shotSeq: row["shot_seq"],
                    createdAtMs: row["created_at_ms"],
                    state: state,
                    liked: row["liked"],
                    assetId: row["asset_id"],
                    pendingFileRelPath: row["pending_file_rel_path"],
                    thumbCacheRelPath: row["thumb_cache_rel_path"],
                    thumbnailState: thumbState,
                    albumState: albumState
                )
            }
        }
    }

    // MARK: - Capture pipeline helpers

    @discardableResult
    func insertOptimisticCapturedPreviewItemAndFlush(now: Date = .init()) throws -> SessionItemSummary {
        let q = try queue()
        guard let sessionId = try currentSessionId() else {
            throw SessionRepositoryError.databaseNotReady
        }

        let nowMs = Self.nowMs(now)
        let itemId = UUID().uuidString
        var summary: SessionItemSummary?

        try q.write { db in
            let shotSeq = try nextShotSeq(db: db, sessionId: sessionId)
            let state = SessionItemState.captured_preview
            let liked = false

            try db.execute(
                sql: """
                INSERT INTO session_items (item_id, session_id, shot_seq, created_at_ms, state, liked)
                VALUES (?, ?, ?, ?, ?, ?)
                """,
                arguments: [itemId, sessionId, shotSeq, nowMs, state.rawValue, liked]
            )

            try db.execute(
                sql: "UPDATE sessions SET last_active_at_ms = ? WHERE session_id = ?",
                arguments: [nowMs, sessionId]
            )

            summary = SessionItemSummary(
                itemId: itemId,
                sessionId: sessionId,
                shotSeq: shotSeq,
                createdAtMs: nowMs,
                state: state,
                liked: liked,
                assetId: nil,
                pendingFileRelPath: nil,
                thumbCacheRelPath: nil,
                thumbnailState: nil,
                albumState: nil
            )
        }

        DatabaseManager.shared.flush(reason: "optimistic_insert")
        return summary!
    }

    func latestSessionItemForCurrentSession() throws -> SessionItemSummary? {
        let q = try queue()
        guard let sessionId = try currentSessionId() else { return nil }

        return try q.read { db in
            let row = try Row.fetchOne(
                db,
                sql: """
                SELECT item_id, session_id, shot_seq, created_at_ms, state, liked,
                       asset_id, pending_file_rel_path, thumb_cache_rel_path,
                       thumbnail_state, album_state
                FROM session_items
                WHERE session_id = ?
                ORDER BY created_at_ms DESC, shot_seq DESC
                LIMIT 1
                """,
                arguments: [sessionId]
            )

            guard let row else { return nil }
            let raw: String = row["state"]
            guard let state = SessionItemState(rawValue: raw) else { return nil }

            let thumbRaw: String? = row["thumbnail_state"]
            let albumRaw: String? = row["album_state"]
            let thumbState = thumbRaw.flatMap { ThumbnailState(rawValue: $0) }
            let albumState = albumRaw.flatMap { AlbumState(rawValue: $0) }

            return SessionItemSummary(
                itemId: row["item_id"],
                sessionId: row["session_id"],
                shotSeq: row["shot_seq"],
                createdAtMs: row["created_at_ms"],
                state: state,
                liked: row["liked"],
                assetId: row["asset_id"],
                pendingFileRelPath: row["pending_file_rel_path"],
                thumbCacheRelPath: row["thumb_cache_rel_path"],
                thumbnailState: thumbState,
                albumState: albumState
            )
        }
    }

    func latestItemsForCurrentSession(limit: Int = 30) throws -> [SessionItemSummary] {
        let q = try queue()
        guard let sessionId = try currentSessionId() else { return [] }

        let n = max(1, min(200, limit))
        return try q.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                SELECT item_id, session_id, shot_seq, created_at_ms, state, liked,
                       asset_id, pending_file_rel_path, thumb_cache_rel_path,
                       thumbnail_state, album_state
                FROM session_items
                WHERE session_id = ?
                ORDER BY created_at_ms DESC, shot_seq DESC
                LIMIT ?
                """,
                arguments: [sessionId, n]
            )

            return rows.compactMap { row in
                let raw: String = row["state"]
                guard let state = SessionItemState(rawValue: raw) else { return nil }

                let thumbRaw: String? = row["thumbnail_state"]
                let albumRaw: String? = row["album_state"]
                let thumbState = thumbRaw.flatMap { ThumbnailState(rawValue: $0) }
                let albumState = albumRaw.flatMap { AlbumState(rawValue: $0) }

                return SessionItemSummary(
                    itemId: row["item_id"],
                    sessionId: row["session_id"],
                    shotSeq: row["shot_seq"],
                    createdAtMs: row["created_at_ms"],
                    state: state,
                    liked: row["liked"],
                    assetId: row["asset_id"],
                    pendingFileRelPath: row["pending_file_rel_path"],
                    thumbCacheRelPath: row["thumb_cache_rel_path"],
                    thumbnailState: thumbState,
                    albumState: albumState
                )
            }
        }
    }

    func sessionItemSummary(itemId: String) throws -> SessionItemSummary? {
        let q = try queue()
        return try q.read { db in
            let row = try Row.fetchOne(
                db,
                sql: """
                SELECT item_id, session_id, shot_seq, created_at_ms, state, liked,
                       asset_id, pending_file_rel_path, thumb_cache_rel_path,
                       thumbnail_state, album_state
                FROM session_items
                WHERE item_id = ?
                LIMIT 1
                """,
                arguments: [itemId]
            )

            guard let row else { return nil }
            let raw: String = row["state"]
            guard let state = SessionItemState(rawValue: raw) else { return nil }

            let thumbRaw: String? = row["thumbnail_state"]
            let albumRaw: String? = row["album_state"]
            let thumbState = thumbRaw.flatMap { ThumbnailState(rawValue: $0) }
            let albumState = albumRaw.flatMap { AlbumState(rawValue: $0) }

            return SessionItemSummary(
                itemId: row["item_id"],
                sessionId: row["session_id"],
                shotSeq: row["shot_seq"],
                createdAtMs: row["created_at_ms"],
                state: state,
                liked: row["liked"],
                assetId: row["asset_id"],
                pendingFileRelPath: row["pending_file_rel_path"],
                thumbCacheRelPath: row["thumb_cache_rel_path"],
                thumbnailState: thumbState,
                albumState: albumState
            )
        }
    }

    func writeFailedItemsForCurrentSession(limit: Int = 50) throws -> [SessionItemSummary] {
        let q = try queue()
        guard let sessionId = try currentSessionId() else { return [] }

        let n = max(1, min(200, limit))
        return try q.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                SELECT item_id, session_id, shot_seq, created_at_ms, state, liked,
                       asset_id, pending_file_rel_path, thumb_cache_rel_path,
                       thumbnail_state, album_state
                FROM session_items
                WHERE session_id = ?
                  AND state = ?
                ORDER BY created_at_ms DESC, shot_seq DESC
                LIMIT ?
                """,
                arguments: [sessionId, SessionItemState.write_failed.rawValue, n]
            )

            return rows.compactMap { row in
                let raw: String = row["state"]
                guard let state = SessionItemState(rawValue: raw) else { return nil }

                let thumbRaw: String? = row["thumbnail_state"]
                let albumRaw: String? = row["album_state"]
                let thumbState = thumbRaw.flatMap { ThumbnailState(rawValue: $0) }
                let albumState = albumRaw.flatMap { AlbumState(rawValue: $0) }

                return SessionItemSummary(
                    itemId: row["item_id"],
                    sessionId: row["session_id"],
                    shotSeq: row["shot_seq"],
                    createdAtMs: row["created_at_ms"],
                    state: state,
                    liked: row["liked"],
                    assetId: row["asset_id"],
                    pendingFileRelPath: row["pending_file_rel_path"],
                    thumbCacheRelPath: row["thumb_cache_rel_path"],
                    thumbnailState: thumbState,
                    albumState: albumState
                )
            }
        }
    }

    func thumbFailedItemsForCurrentSession(limit: Int = 50) throws -> [SessionItemSummary] {
        let q = try queue()
        guard let sessionId = try currentSessionId() else { return [] }

        let n = max(1, min(200, limit))
        return try q.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                SELECT item_id, session_id, shot_seq, created_at_ms, state, liked,
                       asset_id, pending_file_rel_path, thumb_cache_rel_path,
                       thumbnail_state, album_state
                FROM session_items
                WHERE session_id = ?
                  AND thumbnail_state = ?
                ORDER BY created_at_ms DESC, shot_seq DESC
                LIMIT ?
                """,
                arguments: [sessionId, ThumbnailState.failed.rawValue, n]
            )

            return rows.compactMap { row in
                let raw: String = row["state"]
                guard let state = SessionItemState(rawValue: raw) else { return nil }

                let thumbRaw: String? = row["thumbnail_state"]
                let albumRaw: String? = row["album_state"]
                let thumbState = thumbRaw.flatMap { ThumbnailState(rawValue: $0) }
                let albumState = albumRaw.flatMap { AlbumState(rawValue: $0) }

                return SessionItemSummary(
                    itemId: row["item_id"],
                    sessionId: row["session_id"],
                    shotSeq: row["shot_seq"],
                    createdAtMs: row["created_at_ms"],
                    state: state,
                    liked: row["liked"],
                    assetId: row["asset_id"],
                    pendingFileRelPath: row["pending_file_rel_path"],
                    thumbCacheRelPath: row["thumb_cache_rel_path"],
                    thumbnailState: thumbState,
                    albumState: albumState
                )
            }
        }
    }

    func updateSessionItemState(itemId: String, state: SessionItemState, now: Date = .init(), flush: Bool = true) throws {
        let q = try queue()
        let nowMs = Self.nowMs(now)
        try q.write { db in
            try db.execute(
                sql: "UPDATE session_items SET state = ? WHERE item_id = ?",
                arguments: [state.rawValue, itemId]
            )
            try db.execute(
                sql: "UPDATE sessions SET last_active_at_ms = ? WHERE session_id = (SELECT session_id FROM session_items WHERE item_id = ?)",
                arguments: [nowMs, itemId]
            )
        }
        if flush {
            DatabaseManager.shared.flush(reason: "state_\(state.rawValue)")
        }
    }

    func markWriteSuccess(itemId: String, assetId: String, now: Date = .init(), flush: Bool = true) throws {
        let q = try queue()
        let nowMs = Self.nowMs(now)
        try q.write { db in
            try db.execute(
                sql: """
                UPDATE session_items
                SET state = ?,
                    asset_id = ?,
                    album_state = COALESCE(album_state, ?)
                WHERE item_id = ?
                """,
                arguments: [SessionItemState.finalized.rawValue, assetId, AlbumState.queued.rawValue, itemId]
            )
            try db.execute(
                sql: "UPDATE sessions SET last_active_at_ms = ? WHERE session_id = (SELECT session_id FROM session_items WHERE item_id = ?)",
                arguments: [nowMs, itemId]
            )
        }

        print("WriteSuccessMarked: item_id=\(itemId) state=\(SessionItemState.finalized.rawValue) asset_id=\(assetId) album_state_default=\(AlbumState.queued.rawValue)")
        if flush {
            DatabaseManager.shared.flush(reason: SessionItemState.finalized.rawValue)
        }
    }

    func markWriteFailed(itemId: String, now: Date = .init(), flush: Bool = true) throws {
        let q = try queue()
        let nowMs = Self.nowMs(now)
        try q.write { db in
            try db.execute(
                sql: "UPDATE session_items SET state = ?, last_error_at_ms = ? WHERE item_id = ?",
                arguments: [SessionItemState.write_failed.rawValue, nowMs, itemId]
            )

            // Keep session activity updated for TTL correctness.
            try db.execute(
                sql: "UPDATE sessions SET last_active_at_ms = ? WHERE session_id = (SELECT session_id FROM session_items WHERE item_id = ?)",
                arguments: [nowMs, itemId]
            )
        }

        // M4.15: write_failed must be flushed immediately for data safety.
        // Always flush even if callers pass flush=false.
        _ = flush
        DatabaseManager.shared.flush(reason: SessionItemState.write_failed.rawValue)
    }

    func sessionItemPendingFileRelPath(itemId: String) throws -> String? {
        let q = try queue()
        return try q.read { db in
            try String.fetchOne(
                db,
                sql: "SELECT pending_file_rel_path FROM session_items WHERE item_id = ?",
                arguments: [itemId]
            )
        }
    }

    func sessionItemThumbCacheRelPath(itemId: String) throws -> String? {
        let q = try queue()
        return try q.read { db in
            try String.fetchOne(
                db,
                sql: "SELECT thumb_cache_rel_path FROM session_items WHERE item_id = ?",
                arguments: [itemId]
            )
        }
    }

    func updatePendingFileRelPath(itemId: String, relPath: String, now: Date = .init(), flush: Bool = true) throws {
        let q = try queue()
        let nowMs = Self.nowMs(now)
        try q.write { db in
            try db.execute(
                sql: "UPDATE session_items SET pending_file_rel_path = ? WHERE item_id = ?",
                arguments: [relPath, itemId]
            )
            try db.execute(
                sql: "UPDATE sessions SET last_active_at_ms = ? WHERE session_id = (SELECT session_id FROM session_items WHERE item_id = ?)",
                arguments: [nowMs, itemId]
            )
        }
        if flush {
            DatabaseManager.shared.flush(reason: "pending_rel_path")
        }
    }

    func updateThumbCacheRelPath(itemId: String, relPath: String, now: Date = .init(), flush: Bool = true) throws {
        let q = try queue()
        let nowMs = Self.nowMs(now)
        try q.write { db in
            try db.execute(
                sql: "UPDATE session_items SET thumb_cache_rel_path = ? WHERE item_id = ?",
                arguments: [relPath, itemId]
            )
            try db.execute(
                sql: "UPDATE sessions SET last_active_at_ms = ? WHERE session_id = (SELECT session_id FROM session_items WHERE item_id = ?)",
                arguments: [nowMs, itemId]
            )
        }
        if flush {
            DatabaseManager.shared.flush(reason: "thumb_cache_rel_path")
        }
    }

    func updateThumbnailState(itemId: String, state: ThumbnailState?, now: Date = .init(), flush: Bool = true) throws {
        let q = try queue()
        let nowMs = Self.nowMs(now)
        try q.write { db in
            try db.execute(
                sql: "UPDATE session_items SET thumbnail_state = ? WHERE item_id = ?",
                arguments: [state?.rawValue, itemId]
            )
            try db.execute(
                sql: "UPDATE sessions SET last_active_at_ms = ? WHERE session_id = (SELECT session_id FROM session_items WHERE item_id = ?)",
                arguments: [nowMs, itemId]
            )
        }

        print("ThumbnailStateUpdated: item_id=\(itemId) thumbnail_state=\(state?.rawValue ?? "<nil>")")
        if flush {
            DatabaseManager.shared.flush(reason: "thumbnail_state")
        }
    }

    func updateAlbumState(itemId: String, state: AlbumState?, now: Date = .init(), flush: Bool = true) throws {
        let q = try queue()
        let nowMs = Self.nowMs(now)
        try q.write { db in
            try db.execute(
                sql: "UPDATE session_items SET album_state = ? WHERE item_id = ?",
                arguments: [state?.rawValue, itemId]
            )
            try db.execute(
                sql: "UPDATE sessions SET last_active_at_ms = ? WHERE session_id = (SELECT session_id FROM session_items WHERE item_id = ?)",
                arguments: [nowMs, itemId]
            )
        }

        print("AlbumStateUpdated: item_id=\(itemId) album_state=\(state?.rawValue ?? "<nil>")")
        if flush {
            DatabaseManager.shared.flush(reason: "album_state")
        }
    }

    func cleanupItem(itemId: String, flush: Bool = true) throws -> CleanupResult {
        let q = try queue()

        var deleted = 0
        var pendingRel: String?
        var thumbRel: String?

        try q.write { db in
            let row = try Row.fetchOne(
                db,
                sql: "SELECT pending_file_rel_path, thumb_cache_rel_path FROM session_items WHERE item_id = ?",
                arguments: [itemId]
            )
            pendingRel = row?["pending_file_rel_path"]
            thumbRel = row?["thumb_cache_rel_path"]

            try db.execute(
                sql: "DELETE FROM session_items WHERE item_id = ?",
                arguments: [itemId]
            )
            deleted = db.changesCount
        }

        if flush {
            DatabaseManager.shared.flush(reason: "cleanup_item")
        }

        var pendingDeleted = false
        var thumbDeleted = false
        if deleted > 0 {
            if let rel = pendingRel {
                pendingDeleted = (try? PendingFileStore.shared.delete(relativePath: rel)) ?? false
            }
            if let rel = thumbRel {
                thumbDeleted = (try? ThumbCacheStore.shared.delete(relativePath: rel)) ?? false
            }
        }

        return CleanupResult(
            itemId: itemId,
            deletedRowCount: deleted,
            pendingFileRelPath: pendingRel,
            thumbCacheRelPath: thumbRel,
            pendingDeleted: pendingDeleted,
            thumbDeleted: thumbDeleted
        )
    }

    @discardableResult
    func deleteSessionItem(itemId: String, flush: Bool = true) throws -> Int {
        let r = try cleanupItem(itemId: itemId, flush: flush)
        return r.deletedRowCount
    }

    @discardableResult
    func deleteWriteFailedItemsForCurrentSession() throws -> Int {
        let q = try queue()
        guard let id = try currentSessionId() else { return 0 }
        var refs: [(pending: String?, thumb: String?)] = []
        var deleted = 0

        try q.write { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                SELECT pending_file_rel_path, thumb_cache_rel_path
                FROM session_items
                WHERE session_id = ? AND state = ?
                """,
                arguments: [id, SessionItemState.write_failed.rawValue]
            )
            refs = rows.map { row in
                (pending: row["pending_file_rel_path"], thumb: row["thumb_cache_rel_path"])
            }

            try db.execute(
                sql: "DELETE FROM session_items WHERE session_id = ? AND state = ?",
                arguments: [id, SessionItemState.write_failed.rawValue]
            )
            deleted = db.changesCount
        }

        DatabaseManager.shared.flush(reason: "delete_write_failed")

        for r in refs {
            if let rel = r.pending {
                _ = try? PendingFileStore.shared.delete(relativePath: rel)
            }
            if let rel = r.thumb {
                _ = try? ThumbCacheStore.shared.delete(relativePath: rel)
            }
        }

        return deleted
    }
}
