import Foundation

// Single owner of the capture/save pipeline.
//
// Milestone 4.5 scope: create the coordinator shell and prove wiring from the
// shutter button by printing:
// - ShutterTapReceived
// - PipelineStarted
//
// Later milestones will extend this coordinator to:
// - enforce SessionRuleGate checks (M4.7)
// - create optimistic items (M4.8)
// - write pending files (M4.9-M4.10)
// - run PhotoKit writes + verification (M4.11-M4.13)
@MainActor
final class CaptureCoordinator {
    static let shared = CaptureCoordinator()

    private let pipeline = CapturePipeline()

    private var simulateNoPhotoDataOnce: Bool = false
    private var forceFirstVerificationFetchNilOnce: Bool = false

    private init() {}

    func setSimulateNoPhotoDataOnce() {
        simulateNoPhotoDataOnce = true
    }

    func consumeSimulateNoPhotoDataOnce() -> Bool {
        let v = simulateNoPhotoDataOnce
        simulateNoPhotoDataOnce = false
        return v
    }

    func setForceFirstVerificationFetchNilOnce() {
        forceFirstVerificationFetchNilOnce = true
    }

    func consumeForceFirstVerificationFetchNilOnce() -> Bool {
        let v = forceFirstVerificationFetchNilOnce
        forceFirstVerificationFetchNilOnce = false
        return v
    }

    func shutterTapped() {
        print("ShutterTapReceived")
        Task {
            await pipeline.startCapturePipeline()
        }
    }

    func retryWriteFailedItem(itemId: String) async -> Bool {
        await pipeline.retryWriteFailedItem(itemId: itemId)
    }

    func abandonItem(itemId: String) async -> Bool {
        await pipeline.abandonItem(itemId: itemId)
    }
}

// Actor boundary ensures a single serialized pipeline owner.
private actor CapturePipeline {
    func startCapturePipeline() async {
        if let blocked = await blockedReasonIfAny() {
            print("CaptureSkipped:blocked reason=\(blocked)")
            return
        }

        guard let summary = await insertOptimisticItemIfPossible() else {
            print("OptimisticItemMissing")
            return
        }

        print("OptimisticItemInserted: item_id=\(summary.itemId) shot_seq=\(summary.shotSeq) state=\(summary.state.rawValue)")
        NotificationCenter.default.post(name: CaptureEvents.sessionItemsChanged, object: nil)

        // M4.20: kick off thumbnail pipeline.
        await ThumbnailPipeline.shared.requestThumbnail(itemId: summary.itemId)

        let deadlineTask = Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await handleCaptureDataDeadline(itemId: summary.itemId)
        }

        let simulateNoData = await MainActor.run { CaptureCoordinator.shared.consumeSimulateNoPhotoDataOnce() }
        if simulateNoData {
            print("SimulateNoPhotoData: true")
            // Deadline task will convert to capture_failed.
        } else {
            do {
                let rel = PendingFileStore.shared.makeRelativePath(itemId: summary.itemId, fileExtension: "png")
                let data = Self.makeTinyPNGData()
                let url = try PendingFileStore.shared.writeAtomic(data: data, toRelativePath: rel)
                print("PendingFileWritten: item_id=\(summary.itemId) rel_path=\(rel) bytes=\(data.count) url=\(url.path)")

                await MainActor.run {
                    do {
                        try SessionRepository.shared.updatePendingFileRelPath(itemId: summary.itemId, relPath: rel)
                    } catch {
                        print("PendingRelPathUpdateFAILED: \(error)")
                    }
                }

                await MainActor.run {
                    do {
                        try SessionRepository.shared.updateSessionItemState(itemId: summary.itemId, state: .writing)
                        print("StateTransition: item_id=\(summary.itemId) captured_preview->writing")
                    } catch {
                        print("StateTransitionFAILED: \(error)")
                    }
                }

                do {
                    let assetId = try await PhotoLibraryWriter.shared.savePhoto(fileURL: url)
                    print("PhotoKitWriteSuccess: item_id=\(summary.itemId) asset_id=\(assetId)")
                    await MainActor.run {
                        do {
                            try SessionRepository.shared.markWriteSuccess(itemId: summary.itemId, assetId: assetId)
                            print("StateTransition: item_id=\(summary.itemId) writing->finalized")
                        } catch {
                            print("WriteSuccessMarkFAILED: \(error)")
                        }
                    }

                    await verifyWriteAndLog(sessionId: summary.sessionId, assetId: assetId)

                    // M4.24: Best-effort archive to "Just Photo" album (non-blocking).
                    do {
                        let albumId = try await AlbumArchiver.shared.archive(assetLocalIdentifier: assetId)
                        print("AlbumArchiveSuccess: item_id=\(summary.itemId) album_id=\(albumId)")
                        await MainActor.run {
                            do {
                                try SessionRepository.shared.markAlbumAddSuccess(itemId: summary.itemId)
                            } catch {
                                print("AlbumArchiveMarkSuccessFAILED: \(error)")
                            }
                        }
                    } catch {
                        print("AlbumArchiveFAILED: item_id=\(summary.itemId) error=\(error)")
                        await MainActor.run {
                            do {
                                try SessionRepository.shared.updateAlbumState(itemId: summary.itemId, state: .failed)
                                NotificationCenter.default.post(name: CaptureEvents.albumAddFailed, object: nil)
                                Task { await AlbumAddRetryScheduler.shared.kick() }
                            } catch {
                                print("AlbumArchiveMarkFailedFAILED: \(error)")
                            }
                        }
                    }
                } catch {
                    print("PhotoKitWriteFAILED: item_id=\(summary.itemId) error=\(error)")
                    await MainActor.run {
                        do {
                            try SessionRepository.shared.markWriteFailed(itemId: summary.itemId)
                            print("StateTransition: item_id=\(summary.itemId) writing->write_failed")

                            NotificationCenter.default.post(name: CaptureEvents.writeFailed, object: nil)
                        } catch {
                            print("WriteFailedMarkFAILED: \(error)")
                        }
                    }
                }

                deadlineTask.cancel()
            } catch {
                print("PendingFileWriteFAILED: \(error)")
            }
        }

        print("PipelineStarted")
    }

    private func verifyWriteAndLog(sessionId: String, assetId: String) async {
        let scene: String = await MainActor.run {
            (try? SessionRepository.shared.loadCurrentSession()?.scene) ?? "cafe"
        }

        let verificationStart = Date()
        let forcedNil = await MainActor.run { CaptureCoordinator.shared.consumeForceFirstVerificationFetchNilOnce() }

        let firstFetchStart = Date()
        let firstCount = forcedNil ? 0 : PhotoLibraryWriter.shared.fetchAssetCount(localIdentifier: assetId)
        let firstFetchMs = Int(max(0, Date().timeIntervalSince(firstFetchStart) * 1000))
        print("PhotoWriteVerificationFirstFetch: asset_id=\(assetId) count=\(firstCount) first_fetch_ms=\(firstFetchMs) forced_nil=\(forcedNil)")

        if firstCount > 0 {
            await logPhotoWriteVerification(
                sessionId: sessionId,
                scene: scene,
                assetId: assetId,
                firstFetchMs: firstFetchMs,
                retryUsed: false,
                retryDelayMs: 0,
                verifiedWithin2s: true
            )
            return
        }

        // M4.13: Retry once after 500ms if first fetch is empty.
        try? await Task.sleep(nanoseconds: 500_000_000)

        let retryCount = PhotoLibraryWriter.shared.fetchAssetCount(localIdentifier: assetId)
        let elapsedMs = Int(max(0, Date().timeIntervalSince(verificationStart) * 1000))
        let verifiedWithin2s = retryCount > 0 && elapsedMs <= 2_000
        print("PhotoWriteVerificationRetryFetch: asset_id=\(assetId) count=\(retryCount) elapsed_ms=\(elapsedMs)")

        await logPhotoWriteVerification(
            sessionId: sessionId,
            scene: scene,
            assetId: assetId,
            firstFetchMs: firstFetchMs,
            retryUsed: true,
            retryDelayMs: 500,
            verifiedWithin2s: verifiedWithin2s
        )
    }

    private func logPhotoWriteVerification(
        sessionId: String,
        scene: String,
        assetId: String,
        firstFetchMs: Int,
        retryUsed: Bool,
        retryDelayMs: Int,
        verifiedWithin2s: Bool
    ) async {
        await MainActor.run {
            do {
                _ = try DiagnosticsLogger().logPhotoWriteVerification(
                    sessionId: sessionId,
                    scene: scene,
                    assetId: assetId,
                    firstFetchMs: firstFetchMs,
                    retryUsed: retryUsed,
                    retryDelayMs: retryDelayMs,
                    verifiedWithin2s: verifiedWithin2s
                )
            } catch {
                print("PhotoWriteVerificationLogFAILED: \(error)")
            }
        }
    }

    private func handleCaptureDataDeadline(itemId: String) async {
        let relPath: String? = await MainActor.run {
            do {
                return try SessionRepository.shared.sessionItemPendingFileRelPath(itemId: itemId)
            } catch {
                print("CaptureDeadlineReadFAILED: \(error)")
                return nil
            }
        }

        if let relPath, PendingFileStore.shared.fileExists(relativePath: relPath) {
            print("CaptureDeadlineSatisfied: item_id=\(itemId)")
            return
        }

        let defaultRel = PendingFileStore.shared.makeRelativePath(itemId: itemId, fileExtension: "png")
        if PendingFileStore.shared.fileExists(relativePath: defaultRel) {
            print("CaptureDeadlineSatisfied: item_id=\(itemId) (file_exists_no_db_rel_path)")
            return
        }

        let deleted: Int = await MainActor.run {
            do {
                return try SessionRepository.shared.cleanupItem(itemId: itemId).deletedRowCount
            } catch {
                print("CaptureDeadlineDeleteFAILED: \(error)")
                return 0
            }
        }

        guard deleted > 0 else {
            print("CaptureDeadlineNoop: item_id=\(itemId)")
            return
        }

        print("CaptureFailed: item_removed item_id=\(itemId)")
        await MainActor.run {
            NotificationCenter.default.post(name: CaptureEvents.captureFailed, object: nil)
        }
    }

    private static func makeTinyPNGData() -> Data {
        // 1x1 PNG.
        let b64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMB/6X9nN8AAAAASUVORK5CYII="
        return Data(base64Encoded: b64) ?? Data([0x89, 0x50, 0x4E, 0x47])
    }

    private func blockedReasonIfAny() async -> String? {
        await MainActor.run {
            do {
                let counts = try SessionRepository.shared.currentWorksetCounter()
                let workset = counts?.worksetCount ?? 0
                let inflight = counts?.inFlightCount ?? 0
                let writeFailed = try SessionRepository.shared.countWriteFailedItems()

                // M4.7: Do not start capture when blocked by session gates.
                if writeFailed > 0 {
                    return "blocked_by_write_failed write_failed=\(writeFailed)"
                }
                if inflight >= SessionRuleGate.maxInFlightCount {
                    return "in_flight_limit_reached in_flight=\(inflight) max=\(SessionRuleGate.maxInFlightCount)"
                }
                if workset >= SessionRuleGate.maxWorksetCount {
                    return "workset_full workset=\(workset) max=\(SessionRuleGate.maxWorksetCount)"
                }
                return nil
            } catch {
                // Defensive: if DB read fails, don't block the pipeline at this milestone.
                print("CaptureGateReadFAILED: \(error)")
                return nil
            }
        }
    }

    private func insertOptimisticItemIfPossible() async -> SessionRepository.SessionItemSummary? {
        await MainActor.run {
            do {
                return try SessionRepository.shared.insertOptimisticCapturedPreviewItemAndFlush()
            } catch {
                print("OptimisticItemInsertFAILED: \(error)")
                return nil
            }
        }
    }

    // MARK: - Viewer actions

    func retryWriteFailedItem(itemId: String) async -> Bool {
        let summary: SessionRepository.SessionItemSummary? = await MainActor.run {
            try? SessionRepository.shared.sessionItemSummary(itemId: itemId)
        }

        guard let summary else {
            print("RetrySaveNoop: missing item_id=\(itemId)")
            return false
        }

        if summary.state != .write_failed {
            print("RetrySaveNoop: state=\(summary.state.rawValue) item_id=\(itemId)")
            return false
        }

        if let assetId = summary.assetId, !assetId.isEmpty {
            // If the item is marked write_failed but already has an asset id (can happen
            // in debug tools), heal the DB state.
            await MainActor.run {
                do {
                    try SessionRepository.shared.markWriteSuccess(itemId: itemId, assetId: assetId)
                } catch {
                    print("RetrySaveHealMarkSuccessFAILED: \(error)")
                }
            }
            print("RetrySaveHealed: asset_id_present item_id=\(itemId)")
            return true
        }

        var rel = summary.pendingFileRelPath

        if rel == nil {
            let defaultRel = PendingFileStore.shared.makeRelativePath(itemId: itemId, fileExtension: "png")
            if PendingFileStore.shared.fileExists(relativePath: defaultRel) {
                await MainActor.run {
                    do {
                        try SessionRepository.shared.updatePendingFileRelPath(itemId: itemId, relPath: defaultRel)
                    } catch {
                        print("RetrySaveBackfillPendingRelFAILED: \(error)")
                    }
                }
                rel = defaultRel
                print("RetrySaveBackfillPendingRel: item_id=\(itemId) rel=\(defaultRel)")
            }
        }

        #if DEBUG
        if rel == nil {
            // Debug-only healing for synthetic write_failed items (created without a pending file).
            // This prevents the app from being permanently blocked during testing.
            do {
                let defaultRel = PendingFileStore.shared.makeRelativePath(itemId: itemId, fileExtension: "png")
                let data = Self.makeTinyPNGData()
                let url = try PendingFileStore.shared.writeAtomic(data: data, toRelativePath: defaultRel)
                print("RetrySaveHealedPendingWritten: item_id=\(itemId) rel=\(defaultRel) url=\(url.path) bytes=\(data.count)")
                await MainActor.run {
                    do {
                        try SessionRepository.shared.updatePendingFileRelPath(itemId: itemId, relPath: defaultRel)
                    } catch {
                        print("RetrySaveHealedPendingRelUpdateFAILED: \(error)")
                    }
                }
                rel = defaultRel
            } catch {
                print("RetrySaveHealedPendingWriteFAILED: \(error)")
            }
        }
        #endif

        guard let rel else {
            print("RetrySaveFAILED: missing pending_file_rel_path item_id=\(itemId)")
            return false
        }

        let url: URL
        do {
            url = try PendingFileStore.shared.fullURL(forRelativePath: rel)
        } catch {
            print("RetrySaveFAILED: bad pending path item_id=\(itemId) rel=\(rel) error=\(error)")
            return false
        }

        guard FileManager.default.fileExists(atPath: url.path) else {
            print("RetrySaveFAILED: pending missing item_id=\(itemId) url=\(url.path)")
            return false
        }

        await MainActor.run {
            do {
                try SessionRepository.shared.updateSessionItemState(itemId: itemId, state: .writing)
            } catch {
                print("RetrySaveStateToWritingFAILED: \(error)")
            }
        }

        do {
            let assetId = try await PhotoLibraryWriter.shared.savePhoto(fileURL: url)
            print("RetrySavePhotoKitSuccess: item_id=\(itemId) asset_id=\(assetId)")
            await MainActor.run {
                do {
                    try SessionRepository.shared.markWriteSuccess(itemId: itemId, assetId: assetId)
                } catch {
                    print("RetrySaveMarkSuccessFAILED: \(error)")
                }
            }
            return true
        } catch {
            print("RetrySavePhotoKitFAILED: item_id=\(itemId) error=\(error)")
            await MainActor.run {
                do {
                    try SessionRepository.shared.markWriteFailed(itemId: itemId)
                    NotificationCenter.default.post(name: CaptureEvents.writeFailed, object: nil)
                } catch {
                    print("RetrySaveMarkFailedFAILED: \(error)")
                }
            }
            return false
        }
    }

    func abandonItem(itemId: String) async -> Bool {
        let deleted: Int = await MainActor.run {
            do {
                return try SessionRepository.shared.cleanupItem(itemId: itemId).deletedRowCount
            } catch {
                print("AbandonItemFAILED: \(error)")
                return 0
            }
        }

        if deleted > 0 {
            print("AbandonItemOK: item_id=\(itemId)")
            await MainActor.run {
                NotificationCenter.default.post(name: CaptureEvents.writeFailed, object: nil)
            }
            return true
        }

        print("AbandonItemNoop: item_id=\(itemId)")
        return false
    }
}
