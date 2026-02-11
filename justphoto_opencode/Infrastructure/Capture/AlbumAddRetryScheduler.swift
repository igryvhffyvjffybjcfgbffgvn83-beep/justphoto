import Foundation

// M4.27: Automatic retry backoff for album_add_failed.
// Same item auto-retries at most 3 times with backoff: 1s / 3s / 10s.
actor AlbumAddRetryScheduler {
    static let shared = AlbumAddRetryScheduler()

    private let maxAttempts = 3
    private let backoffMs: [Int64] = [1_000, 3_000, 10_000]

    private var tasks: [String: Task<Void, Never>] = [:]

    private init() {}

#if DEBUG
    private let debugProbeId = "debug_cancel_probe_album_retry"
#endif

    func kick() async {
        let candidates: [SessionRepository.AlbumAddRetryCandidate] = await MainActor.run {
            (try? SessionRepository.shared.albumAddFailedAutoRetryCandidates(maxAttempts: maxAttempts)) ?? []
        }

        for c in candidates {
            await scheduleIfNeeded(candidate: c)
        }
    }

    func cancel(itemIds: [String]) {
        for id in itemIds {
            tasks[id]?.cancel()
            tasks[id] = nil
        }
    }

    private func scheduleIfNeeded(candidate: SessionRepository.AlbumAddRetryCandidate) async {
        let itemId = candidate.itemId
        guard tasks[itemId] == nil else { return }
        guard candidate.retryCount < maxAttempts else { return }

        let now = Date()
        let nowMs = Int64(now.timeIntervalSince1970 * 1000)

        var nextAtMs = candidate.nextAtMs
        if nextAtMs == nil {
            let delay = backoffDelayMs(retryCount: candidate.retryCount)
            nextAtMs = await MainActor.run {
                (try? SessionRepository.shared.scheduleAlbumAutoRetryIfNeeded(itemId: itemId, now: now, delayMs: delay))
            }
        }

        let delayMs = max(Int64(0), (nextAtMs ?? nowMs) - nowMs)
        JPDebugPrint("AlbumAutoRetryScheduled: item_id=\(itemId) retry_count=\(candidate.retryCount) delay_ms=\(delayMs)")

        tasks[itemId] = Task {
            do {
                try await Task.sleep(nanoseconds: UInt64(delayMs) * 1_000_000)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            await attempt(itemId: itemId, assetId: candidate.assetId, expectedRetryCount: candidate.retryCount)
        }
    }

    private func attempt(itemId: String, assetId: String, expectedRetryCount: Int) async {
        guard !Task.isCancelled else { return }
        tasks[itemId] = nil

        let current: SessionRepository.AlbumAddRetryCandidate? = await MainActor.run {
            try? SessionRepository.shared.albumAddRetryCandidate(itemId: itemId)
        }

        guard let current else { return }
        guard current.albumState == .failed else { return }
        guard current.coreState == .finalized else { return }
        guard current.retryCount == expectedRetryCount else {
            // Another path (manual retry / another scheduler run) already progressed it.
            return
        }

        await MainActor.run {
            do {
                try SessionRepository.shared.beginAlbumAutoRetryAttempt(itemId: itemId, now: Date())
            } catch {
                JPDebugPrint("AlbumAutoRetryBeginFAILED: \(error)")
            }
        }

        JPDebugPrint("AlbumAutoRetryAttempt: item_id=\(itemId) retry_count=\(expectedRetryCount)")

        do {
            _ = try await AlbumArchiver.shared.archive(assetLocalIdentifier: assetId)
            JPDebugPrint("AlbumAutoRetrySuccess: item_id=\(itemId)")
            await MainActor.run {
                do {
                    try SessionRepository.shared.markAlbumAddSuccess(itemId: itemId)
                } catch {
                    JPDebugPrint("AlbumAutoRetryMarkSuccessFAILED: \(error)")
                }
            }
        } catch {
            if case AlbumArchiverError.assetNotFound = error {
                // Phantom/missing asset: heal locally and stop retrying.
                if let report = await PhantomAssetHealer.shared.healIfNeeded(itemId: itemId, assetId: assetId, source: "album_auto_retry") {
                    JPDebugPrint("AlbumAutoRetryHealedPhantom: item_id=\(itemId) action=\(report.healAction.rawValue)")
                    return
                }
            }

            JPDebugPrint("AlbumAutoRetryFAILED: item_id=\(itemId) error=\(error)")

            let nextDelayMs = backoffDelayMs(retryCount: expectedRetryCount + 1)
            await MainActor.run {
                do {
                    try SessionRepository.shared.bumpAlbumAutoRetryFailure(
                        itemId: itemId,
                        now: Date(),
                        nextDelayMs: (expectedRetryCount + 1) < maxAttempts ? nextDelayMs : nil
                    )
                } catch {
                    JPDebugPrint("AlbumAutoRetryBumpFAILED: \(error)")
                }
            }

            await kick()
        }
    }

    private func backoffDelayMs(retryCount: Int) -> Int64 {
        // retryCount=0 -> 1s, 1 -> 3s, 2 -> 10s; clamp defensively.
        if retryCount <= 0 { return backoffMs[0] }
        if retryCount >= backoffMs.count { return backoffMs[backoffMs.count - 1] }
        return backoffMs[retryCount]
    }

#if DEBUG
    func debugCancelProbe() async {
        let id = debugProbeId
        tasks[id]?.cancel()
        tasks[id] = Task {
            do {
                try await Task.sleep(nanoseconds: 2_000_000_000)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            JPDebugPrint("AlbumAutoRetryCancelProbeFired: item_id=\(id)")
        }

        do {
            try await Task.sleep(nanoseconds: 100_000_000)
        } catch {
            return
        }
        guard !Task.isCancelled else { return }

        cancel(itemIds: [id])
        JPDebugPrint("AlbumAutoRetryCancelProbeCancelled: item_id=\(id)")
    }
#endif
}
