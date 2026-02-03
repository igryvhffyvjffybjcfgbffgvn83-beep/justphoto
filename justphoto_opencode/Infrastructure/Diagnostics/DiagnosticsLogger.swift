import Foundation

final class DiagnosticsLogger: Sendable {
    init() {}

    private static let dayStampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    func encodeJSONLine(_ event: DiagnosticsEvent) throws -> String {
        let data = try JSONEncoder().encode(event)
        guard let line = String(data: data, encoding: .utf8) else {
            throw NSError(domain: "DiagnosticsLogger", code: 1)
        }
        return line
    }

    func diagnosticsDirectoryURL() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )

        let dir = base.appendingPathComponent("JustPhoto", isDirectory: true)
            .appendingPathComponent("Diagnostics", isDirectory: true)

        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func currentLogFileURL(now: Date = .init()) throws -> URL {
        let dir = try diagnosticsDirectoryURL()
        let day = Self.dayStampFormatter.string(from: now)
        return dir.appendingPathComponent("diagnostics-\(day).jsonl", isDirectory: false)
    }

    func fileSizeBytes(at url: URL) -> Int64 {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        return Int64(values?.fileSize ?? 0)
    }

    @discardableResult
    func appendJSONLine(_ jsonLine: String) throws -> (fileURL: URL, bytesBefore: Int64, bytesAfter: Int64) {
        let url = try currentLogFileURL()
        let before = fileSizeBytes(at: url)

        let line = jsonLine + "\n"
        let data = Data(line.utf8)

        if FileManager.default.fileExists(atPath: url.path) {
            let handle = try FileHandle(forWritingTo: url)
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
            try handle.close()
        } else {
            try data.write(to: url, options: Data.WritingOptions.atomic)
        }

        let after = fileSizeBytes(at: url)
        return (fileURL: url, bytesBefore: before, bytesAfter: after)
    }
}

extension DiagnosticsLogger {
    private static func nowMs(now: Date) -> Int64 {
        Int64(now.timeIntervalSince1970 * 1000)
    }

    @discardableResult
    private func appendEvent(_ event: DiagnosticsEvent) throws -> (fileURL: URL, jsonLine: String) {
        let line = try encodeJSONLine(event)
        let result = try appendJSONLine(line)
        return (fileURL: result.fileURL, jsonLine: line)
    }

    // MARK: - PRD Appendix A.13 Required Events (write helpers)

    @discardableResult
    func logWithRefMatchState(
        sessionId: String,
        scene: String,
        match: Bool,
        requiredDimensions: [String],
        blockedBy: [String],
        mirrorApplied: Bool? = nil,
        now: Date = .init()
    ) throws -> (fileURL: URL, jsonLine: String) {
        var payload: [String: String] = [
            "match": match ? "true" : "false",
            "required_dimensions": requiredDimensions.joined(separator: ","),
            "blocked_by": blockedBy.joined(separator: ",")
        ]

        if let mirrorApplied {
            payload["mirror_applied"] = mirrorApplied ? "true" : "false"
        }

        let e = DiagnosticsEvent(
            ts_ms: Self.nowMs(now: now),
            session_id: sessionId,
            event: "withref_match_state",
            scene: scene,
            payload: payload
        )
        return try appendEvent(e)
    }

    @discardableResult
    func logWithRefFallback(
        sessionId: String,
        scene: String,
        reason: String,
        missing: [String] = [],
        now: Date = .init()
    ) throws -> (fileURL: URL, jsonLine: String) {
        let e = DiagnosticsEvent(
            ts_ms: Self.nowMs(now: now),
            session_id: sessionId,
            event: "withref_fallback",
            scene: scene,
            payload: [
                "reason": reason,
                "missing": missing.joined(separator: ",")
            ]
        )
        return try appendEvent(e)
    }

    @discardableResult
    func logPhotoWriteVerification(
        sessionId: String,
        scene: String,
        assetId: String,
        firstFetchMs: Int,
        retryUsed: Bool,
        retryDelayMs: Int,
        verifiedWithin2s: Bool,
        now: Date = .init()
    ) throws -> (fileURL: URL, jsonLine: String) {
        let e = DiagnosticsEvent(
            ts_ms: Self.nowMs(now: now),
            session_id: sessionId,
            event: "photo_write_verification",
            scene: scene,
            payload: [
                "asset_id": assetId,
                "first_fetch_ms": String(firstFetchMs),
                "retry_used": retryUsed ? "true" : "false",
                "retry_delay_ms": String(retryDelayMs),
                "verified_within_2s": verifiedWithin2s ? "true" : "false"
            ]
        )
        return try appendEvent(e)
    }

    @discardableResult
    func logPhantomAssetDetected(
        sessionId: String,
        scene: String,
        assetIdHash: String,
        authSnapshot: String,
        healAction: String,
        now: Date = .init()
    ) throws -> (fileURL: URL, jsonLine: String) {
        let e = DiagnosticsEvent(
            ts_ms: Self.nowMs(now: now),
            session_id: sessionId,
            event: "phantom_asset_detected",
            scene: scene,
            payload: [
                "asset_id_hash": assetIdHash,
                "auth_snapshot": authSnapshot,
                "heal_action": healAction
            ]
        )
        return try appendEvent(e)
    }

    @discardableResult
    func logODRAutoRetry(
        sessionId: String,
        scene: String,
        stateBefore: String,
        debounceMs: Int,
        result: String,
        now: Date = .init()
    ) throws -> (fileURL: URL, jsonLine: String) {
        let e = DiagnosticsEvent(
            ts_ms: Self.nowMs(now: now),
            session_id: sessionId,
            event: "odr_auto_retry",
            scene: scene,
            payload: [
                "state_before": stateBefore,
                "debounce_ms": String(debounceMs),
                "result": result
            ]
        )
        return try appendEvent(e)
    }
}
