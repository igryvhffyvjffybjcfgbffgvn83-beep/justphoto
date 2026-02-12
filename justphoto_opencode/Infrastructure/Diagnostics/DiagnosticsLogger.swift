import Foundation

final class DiagnosticsLogger: Sendable {
    nonisolated init() {}

    // Avoid DateFormatter (not thread-safe) because this type is used from
    // non-main executors (Swift 6 default isolation is MainActor).
    private nonisolated static let appendLock = NSLock()

    private nonisolated static func dayStampUTC(_ now: Date) -> String {
        let tz = TimeZone(secondsFromGMT: 0) ?? .gmt
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        let c = cal.dateComponents([.year, .month, .day], from: now)
        let y = c.year ?? 1970
        let m = c.month ?? 1
        let d = c.day ?? 1
        return String(format: "%04d-%02d-%02d", y, m, d)
    }

    nonisolated func encodeJSONLine(_ event: DiagnosticsEvent) throws -> String {
        let data = try JSONEncoder().encode(event)
        guard let line = String(data: data, encoding: .utf8) else {
            throw NSError(domain: "DiagnosticsLogger", code: 1)
        }
        return line
    }

    nonisolated func diagnosticsDirectoryURL() throws -> URL {
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

    nonisolated func currentLogFileURL(now: Date = .init()) throws -> URL {
        let dir = try diagnosticsDirectoryURL()
        let day = Self.dayStampUTC(now)
        return dir.appendingPathComponent("diagnostics-\(day).jsonl", isDirectory: false)
    }

    nonisolated func fileSizeBytes(at url: URL) -> Int64 {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        return Int64(values?.fileSize ?? 0)
    }

    @discardableResult
    nonisolated func appendJSONLine(_ jsonLine: String) throws -> (fileURL: URL, bytesBefore: Int64, bytesAfter: Int64) {
        Self.appendLock.lock()
        defer { Self.appendLock.unlock() }

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
    private nonisolated static func nowMs(now: Date) -> Int64 {
        Int64(now.timeIntervalSince1970 * 1000)
    }

    @discardableResult
    private nonisolated func appendEvent(_ event: DiagnosticsEvent) throws -> (fileURL: URL, jsonLine: String) {
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
    nonisolated func logPhantomAssetDetected(
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

// MARK: - A.12 Prompt event logging (local-only)

actor DiagnosticsEventWriter {
    static let shared = DiagnosticsEventWriter()

    private let logger = DiagnosticsLogger()

    private init() {}

    private static func nowMs(now: Date) -> Int64 {
        Int64(now.timeIntervalSince1970 * 1000)
    }

    private static func encodePromptPayload(_ payload: [String: PromptPayloadValue]) -> String {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(payload)
            return String(decoding: data, as: UTF8.self)
        } catch {
            // Best-effort: keep logs writable even if payload encoding fails.
            return "{}"
        }
    }

    private static func promptRequiredFields(_ prompt: Prompt) -> [String: String] {
        var out: [String: String] = [
            "key": prompt.key,
            "level": prompt.level.rawValue,
            "surface": prompt.surface.rawValue,
            "priority": String(prompt.priority),
            "blocksShutter": prompt.blocksShutter ? "true" : "false",
            "emittedAt": String(Int64(prompt.emittedAt.timeIntervalSince1970 * 1000)),
            "payload": encodePromptPayload(prompt.payload)
        ]

        // Optional but useful for QA/debugging.
        out["prompt_id"] = prompt.id
        return out
    }

    private func append(event: DiagnosticsEvent) {
        do {
            let line = try logger.encodeJSONLine(event)
            _ = try logger.appendJSONLine(line)
        } catch {
            JPDebugPrint("DiagnosticsAppendFAILED: \(event.event): \(error)")
        }
    }

    func logPromptShown(sessionId: String, scene: String, prompt: Prompt, now: Date = .init()) {
        let e = DiagnosticsEvent(
            ts_ms: Self.nowMs(now: now),
            session_id: sessionId,
            event: "prompt_shown",
            scene: scene,
            payload: Self.promptRequiredFields(prompt)
        )
        append(event: e)
    }

    func logPromptDismissed(
        sessionId: String,
        scene: String,
        prompt: Prompt,
        dismissReason: DismissReason,
        now: Date = .init()
    ) {
        var payload = Self.promptRequiredFields(prompt)
        payload["dismissReason"] = dismissReason.rawValue

        let e = DiagnosticsEvent(
            ts_ms: Self.nowMs(now: now),
            session_id: sessionId,
            event: "prompt_dismissed",
            scene: scene,
            payload: payload
        )
        append(event: e)
    }

    func logPromptActionTapped(
        sessionId: String,
        scene: String,
        prompt: Prompt,
        actionId: String,
        now: Date = .init()
    ) {
        var payload = Self.promptRequiredFields(prompt)
        payload["actionId"] = actionId

        let e = DiagnosticsEvent(
            ts_ms: Self.nowMs(now: now),
            session_id: sessionId,
            event: "prompt_action_tapped",
            scene: scene,
            payload: payload
        )
        append(event: e)
    }

    // MARK: - A.13 + raw append (serialized)

    func appendJSONLine(_ jsonLine: String) -> (fileURL: URL, bytesBefore: Int64, bytesAfter: Int64)? {
        do {
            return try logger.appendJSONLine(jsonLine)
        } catch {
            JPDebugPrint("DiagnosticsAppendFAILED: raw_line: \(error)")
            return nil
        }
    }

    func logWithRefMatchState(
        sessionId: String,
        scene: String,
        match: Bool,
        requiredDimensions: [String],
        blockedBy: [String],
        mirrorApplied: Bool? = nil,
        now: Date = .init()
    ) -> (fileURL: URL, jsonLine: String)? {
        do {
            return try logger.logWithRefMatchState(
                sessionId: sessionId,
                scene: scene,
                match: match,
                requiredDimensions: requiredDimensions,
                blockedBy: blockedBy,
                mirrorApplied: mirrorApplied,
                now: now
            )
        } catch {
            JPDebugPrint("DiagnosticsAppendFAILED: withref_match_state: \(error)")
            return nil
        }
    }

    func logWithRefFallback(
        sessionId: String,
        scene: String,
        reason: String,
        missing: [String] = [],
        now: Date = .init()
    ) -> (fileURL: URL, jsonLine: String)? {
        do {
            return try logger.logWithRefFallback(
                sessionId: sessionId,
                scene: scene,
                reason: reason,
                missing: missing,
                now: now
            )
        } catch {
            JPDebugPrint("DiagnosticsAppendFAILED: withref_fallback: \(error)")
            return nil
        }
    }

    func logPhotoWriteVerification(
        sessionId: String,
        scene: String,
        assetId: String,
        firstFetchMs: Int,
        retryUsed: Bool,
        retryDelayMs: Int,
        verifiedWithin2s: Bool,
        now: Date = .init()
    ) -> (fileURL: URL, jsonLine: String)? {
        do {
            return try logger.logPhotoWriteVerification(
                sessionId: sessionId,
                scene: scene,
                assetId: assetId,
                firstFetchMs: firstFetchMs,
                retryUsed: retryUsed,
                retryDelayMs: retryDelayMs,
                verifiedWithin2s: verifiedWithin2s,
                now: now
            )
        } catch {
            JPDebugPrint("DiagnosticsAppendFAILED: photo_write_verification: \(error)")
            return nil
        }
    }

    func logPhantomAssetDetected(
        sessionId: String,
        scene: String,
        assetIdHash: String,
        authSnapshot: String,
        healAction: String,
        now: Date = .init()
    ) -> (fileURL: URL, jsonLine: String)? {
        do {
            return try logger.logPhantomAssetDetected(
                sessionId: sessionId,
                scene: scene,
                assetIdHash: assetIdHash,
                authSnapshot: authSnapshot,
                healAction: healAction,
                now: now
            )
        } catch {
            JPDebugPrint("DiagnosticsAppendFAILED: phantom_asset_detected: \(error)")
            return nil
        }
    }

    func logODRAutoRetry(
        sessionId: String,
        scene: String,
        stateBefore: String,
        debounceMs: Int,
        result: String,
        now: Date = .init()
    ) -> (fileURL: URL, jsonLine: String)? {
        do {
            return try logger.logODRAutoRetry(
                sessionId: sessionId,
                scene: scene,
                stateBefore: stateBefore,
                debounceMs: debounceMs,
                result: result,
                now: now
            )
        } catch {
            JPDebugPrint("DiagnosticsAppendFAILED: odr_auto_retry: \(error)")
            return nil
        }
    }
}
