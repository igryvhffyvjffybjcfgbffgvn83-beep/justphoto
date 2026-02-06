import Foundation

// M4.20: Centralized thumbnail pipeline shell.
// Later milestones implement real thumbnail generation, 5s/30s thresholds, and rebuild.
actor ThumbnailPipeline {
    static let shared = ThumbnailPipeline()

    private let thumbFailThresholdNs: UInt64 = 5_000_000_000
    private let defaultThumbGenDelayNs: UInt64 = 300_000_000

    // Debug only: when set, delay thumbnail generation.
    private var debugDelaySeconds: Double? = nil

    private enum ScheduleKind: Sendable {
        case fail
        case gen
    }

    private struct Schedule: Sendable {
        let token: UUID
        var failTask: Task<Void, Never>?
        var genTask: Task<Void, Never>?
    }

    private var scheduled: [String: Schedule] = [:]

    private init() {}

    func requestThumbnail(itemId: String) {
        #if DEBUG
        print("ThumbPipelineStarted:itemId=\(itemId)")
        #endif

        // Cancel any previous scheduled work for this item.
        if let s = scheduled[itemId] {
            s.failTask?.cancel()
            s.genTask?.cancel()
            scheduled[itemId] = nil
        }

        let token = UUID()

        let delayNs: UInt64
        if let d = debugDelaySeconds {
            delayNs = UInt64(max(0, d) * 1_000_000_000)
        } else {
            delayNs = defaultThumbGenDelayNs
        }

        let failTask = Task {
            defer {
                Task {
                    await self.markScheduledTaskCompleted(itemId: itemId, token: token, kind: .fail)
                }
            }
            do {
                try await Task.sleep(nanoseconds: self.thumbFailThresholdNs)
            } catch {
                return
            }

            guard await self.isCurrentSchedule(itemId: itemId, token: token) else { return }
            await self.markThumbFailedIfNeeded(itemId: itemId)
        }

        let genTask = Task {
            defer {
                Task {
                    await self.markScheduledTaskCompleted(itemId: itemId, token: token, kind: .gen)
                }
            }
            do {
                try await Task.sleep(nanoseconds: delayNs)
            } catch {
                return
            }

            guard await self.isCurrentSchedule(itemId: itemId, token: token) else { return }
            await self.generateThumbIfPossible(itemId: itemId)
        }

        scheduled[itemId] = Schedule(token: token, failTask: failTask, genTask: genTask)
    }

    func setDebugDelay(seconds: Double?) {
        debugDelaySeconds = seconds
        #if DEBUG
        print("ThumbPipelineDebugDelaySet: \(seconds.map(String.init(describing:)) ?? "<nil>")")
        #endif
    }

    // M4.23: Viewer action "重建缩略".
    func rebuildThumbnail(itemId: String) async {
        #if DEBUG
        print("ThumbRebuildRequested:itemId=\(itemId)")
        #endif

        // Cancel any scheduled work; rebuild attempts immediately.
        if let s = scheduled[itemId] {
            s.failTask?.cancel()
            s.genTask?.cancel()
            scheduled[itemId] = nil
        }

        await generateThumbNow(itemId: itemId)
    }

    private func markScheduledTaskCompleted(itemId: String, token: UUID, kind: ScheduleKind) async {
        guard var s = scheduled[itemId], s.token == token else { return }
        switch kind {
        case .fail:
            s.failTask = nil
        case .gen:
            s.genTask = nil
        }

        if s.failTask == nil && s.genTask == nil {
            scheduled[itemId] = nil
        } else {
            scheduled[itemId] = s
        }
    }

    private func isCurrentSchedule(itemId: String, token: UUID) async -> Bool {
        scheduled[itemId]?.token == token
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
                #if DEBUG
                print("ThumbFailedMarked:itemId=\(itemId)")
                #endif
                NotificationCenter.default.post(name: CaptureEvents.sessionItemsChanged, object: nil)
            } catch {
                #if DEBUG
                print("ThumbFailedMarkFAILED: \(error)")
                #endif
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
                    #if DEBUG
                    print("ThumbRelPathUpdateFAILED: \(error)")
                    #endif
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
                        #if DEBUG
                        print("ThumbReadyMarked:itemId=\(itemId)")
                        #endif
                        NotificationCenter.default.post(name: CaptureEvents.sessionItemsChanged, object: nil)
                    } catch {
                        #if DEBUG
                        print("ThumbReadyMarkFAILED: \(error)")
                        #endif
                    }
                }
            } else {
                #if DEBUG
                print("ThumbGeneratedLateNoHeal:itemId=\(itemId) state=\(state?.rawValue ?? "<nil>")")
                #endif
            }
        } catch {
            #if DEBUG
            print("ThumbGenerateFAILED: \(error)")
            #endif
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
                    #if DEBUG
                    print("ThumbRelPathUpdateFAILED: \(error)")
                    #endif
                }
            }

            let state: SessionItemState? = await MainActor.run {
                (try? SessionRepository.shared.sessionItemSummary(itemId: itemId))?.state
            }

            // Don't touch write_failed items here.
            guard state != .write_failed else {
                #if DEBUG
                print("ThumbRebuildNoopWriteFailed:itemId=\(itemId)")
                #endif
                return
            }

            await MainActor.run {
                do {
                    try SessionRepository.shared.updateThumbnailState(itemId: itemId, state: .ready)
                    #if DEBUG
                    print("ThumbRebuildReadyMarked:itemId=\(itemId)")
                    #endif
                } catch {
                    #if DEBUG
                    print("ThumbRebuildReadyMarkFAILED: \(error)")
                    #endif
                }
            }
        } catch {
            #if DEBUG
            print("ThumbRebuildFAILED: \(error)")
            #endif
        }
    }
}
