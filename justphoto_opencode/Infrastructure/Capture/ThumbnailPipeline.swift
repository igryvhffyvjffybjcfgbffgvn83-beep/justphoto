import Foundation

// M4.20: Centralized thumbnail pipeline shell.
// Later milestones implement real thumbnail generation, 5s/30s thresholds, and rebuild.
actor ThumbnailPipeline {
    static let shared = ThumbnailPipeline()

    private let thumbFailThresholdNs: UInt64 = 5_000_000_000
    private let defaultThumbGenDelayNs: UInt64 = 300_000_000

    // Debug only: when set, delay thumbnail generation.
    private var debugDelaySeconds: Double? = nil

    private var scheduled: [String: (failTask: Task<Void, Never>, genTask: Task<Void, Never>)] = [:]

    private init() {}

    func requestThumbnail(itemId: String) {
        print("ThumbPipelineStarted:itemId=\(itemId)")

        // Cancel any previous scheduled work for this item.
        if let s = scheduled[itemId] {
            s.failTask.cancel()
            s.genTask.cancel()
            scheduled[itemId] = nil
        }

        let delayNs: UInt64
        if let d = debugDelaySeconds {
            delayNs = UInt64(max(0, d) * 1_000_000_000)
        } else {
            delayNs = defaultThumbGenDelayNs
        }

        let failTask = Task {
            try? await Task.sleep(nanoseconds: self.thumbFailThresholdNs)
            await self.markThumbFailedIfNeeded(itemId: itemId)
        }

        let genTask = Task {
            try? await Task.sleep(nanoseconds: delayNs)
            await self.generateThumbIfPossible(itemId: itemId)
        }

        scheduled[itemId] = (failTask: failTask, genTask: genTask)
    }

    func setDebugDelay(seconds: Double?) {
        debugDelaySeconds = seconds
        print("ThumbPipelineDebugDelaySet: \(seconds.map(String.init(describing:)) ?? "<nil>")")
    }

    // M4.23: Viewer action "重建缩略".
    func rebuildThumbnail(itemId: String) async {
        print("ThumbRebuildRequested:itemId=\(itemId)")

        // Cancel any scheduled work; rebuild attempts immediately.
        if let s = scheduled[itemId] {
            s.failTask.cancel()
            s.genTask.cancel()
            scheduled[itemId] = nil
        }

        await generateThumbNow(itemId: itemId)
    }

    private func markThumbFailedIfNeeded(itemId: String) async {
        let summary: SessionRepository.SessionItemSummary? = await MainActor.run {
            try? SessionRepository.shared.sessionItemSummary(itemId: itemId)
        }

        guard let summary else { return }
        if summary.thumbnailState == .ready { return }
        if summary.state == .write_failed { return }

        let thumbRel: String? = await MainActor.run {
            try? SessionRepository.shared.sessionItemThumbCacheRelPath(itemId: itemId)
        }

        if let thumbRel, ThumbCacheStore.shared.fileExists(relativePath: thumbRel) {
            return
        }

        await MainActor.run {
            do {
                try SessionRepository.shared.updateThumbnailState(itemId: itemId, state: .failed)
                print("ThumbFailedMarked:itemId=\(itemId)")
                NotificationCenter.default.post(name: CaptureEvents.sessionItemsChanged, object: nil)
            } catch {
                print("ThumbFailedMarkFAILED: \(error)")
            }
        }
    }

    private func generateThumbIfPossible(itemId: String) async {
        // For M4.20/4.21 we generate a tiny placeholder thumb file.
        do {
            let rel = ThumbCacheStore.shared.makeRelativePath(itemId: itemId, fileExtension: "png")
            let data = Self.makeTinyPNGData()
            _ = try ThumbCacheStore.shared.writeAtomic(data: data, toRelativePath: rel)
            await MainActor.run {
                do {
                    try SessionRepository.shared.updateThumbCacheRelPath(itemId: itemId, relPath: rel)
                } catch {
                    print("ThumbRelPathUpdateFAILED: \(error)")
                }
            }

            let state: SessionItemState? = await MainActor.run {
                (try? SessionRepository.shared.sessionItemSummary(itemId: itemId))?.state
            }

            // M4.22: late self-heal. If a real thumbnail arrives later, clear thumb_failed.
            if let state, state != .write_failed {
                await MainActor.run {
                    do {
                        try SessionRepository.shared.updateThumbnailState(itemId: itemId, state: .ready)
                        print("ThumbReadyMarked:itemId=\(itemId)")
                        NotificationCenter.default.post(name: CaptureEvents.sessionItemsChanged, object: nil)
                    } catch {
                        print("ThumbReadyMarkFAILED: \(error)")
                    }
                }
            } else {
                print("ThumbGeneratedLateNoHeal:itemId=\(itemId) state=\(state?.rawValue ?? "<nil>")")
            }
        } catch {
            print("ThumbGenerateFAILED: \(error)")
        }
    }

    private static func makeTinyPNGData() -> Data {
        let b64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMB/6X9nN8AAAAASUVORK5CYII="
        return Data(base64Encoded: b64) ?? Data([0x89, 0x50, 0x4E, 0x47])
    }

    private func generateThumbNow(itemId: String) async {
        do {
            let rel = ThumbCacheStore.shared.makeRelativePath(itemId: itemId, fileExtension: "png")
            let data = Self.makeTinyPNGData()
            _ = try ThumbCacheStore.shared.writeAtomic(data: data, toRelativePath: rel)

            await MainActor.run {
                do {
                    try SessionRepository.shared.updateThumbCacheRelPath(itemId: itemId, relPath: rel)
                } catch {
                    print("ThumbRelPathUpdateFAILED: \(error)")
                }
            }

            let state: SessionItemState? = await MainActor.run {
                (try? SessionRepository.shared.sessionItemSummary(itemId: itemId))?.state
            }

            // Don't touch write_failed items here.
            guard state != .write_failed else {
                print("ThumbRebuildNoopWriteFailed:itemId=\(itemId)")
                return
            }

            await MainActor.run {
                do {
                    try SessionRepository.shared.updateThumbnailState(itemId: itemId, state: .ready)
                    print("ThumbRebuildReadyMarked:itemId=\(itemId)")
                } catch {
                    print("ThumbRebuildReadyMarkFAILED: \(error)")
                }
            }
        } catch {
            print("ThumbRebuildFAILED: \(error)")
        }
    }
}
