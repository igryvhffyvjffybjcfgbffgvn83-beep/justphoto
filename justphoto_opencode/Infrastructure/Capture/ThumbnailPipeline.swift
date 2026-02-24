import Foundation
import ImageIO
import UniformTypeIdentifiers

// M4.20: Centralized thumbnail pipeline shell.
// M6.17+: Generate real thumbnails from pending files and keep optimistic placeholders separate.
actor ThumbnailPipeline {
    static let shared = ThumbnailPipeline()

    private let thumbFailThresholdNs: UInt64 = 5_000_000_000
    private let defaultThumbGenDelayNs: UInt64 = 300_000_000
    private let thumbFilmstripPx: Int = 256
    private let thumbJpegQuality: Double = 0.85
    private let pendingMinBytes: Int = 50_000
    private let pendingRetryDelaysNs: [UInt64] = [300_000_000, 1_000_000_000]

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

        Task {
            await self.ensureOptimisticThumb(itemId: itemId)
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

        if let thumbRel,
           let url = try? ThumbCacheStore.shared.fullURL(forRelativePath: thumbRel),
           isRealThumb(relPath: thumbRel, url: url) {
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
        let delays: [UInt64] = [0] + pendingRetryDelaysNs
        for delay in delays {
            if Task.isCancelled { return }
            if delay > 0 {
                do {
                    try await Task.sleep(nanoseconds: delay)
                } catch {
                    return
                }
            }

            if await generateThumbFromPending(itemId: itemId) {
                return
            }
        }
    }

    private static func makeTinyPNGData() -> Data {
        let b64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMB/6X9nN8AAAAASUVORK5CYII="
        return Data(base64Encoded: b64) ?? Data([0x89, 0x50, 0x4E, 0x47])
    }

    private func generateThumbNow(itemId: String) async {
        _ = await generateThumbFromPending(itemId: itemId)
    }

    private func ensureOptimisticThumb(itemId: String) async {
        let existing: String? = await MainActor.run {
            try? SessionRepository.shared.sessionItemThumbCacheRelPath(itemId: itemId)
        }
        if existing != nil { return }

        do {
            let rel = ThumbCacheStore.shared.makeRelativePath(itemId: itemId, fileExtension: "png")
            let data = Self.makeTinyPNGData()
            _ = try ThumbCacheStore.shared.writeAtomic(data: data, toRelativePath: rel)
            await MainActor.run {
                do {
                    try SessionRepository.shared.updateThumbCacheRelPath(itemId: itemId, relPath: rel)
                } catch {
                    #if DEBUG
                    print("ThumbOptimisticRelPathUpdateFAILED: \(error)")
                    #endif
                }
            }
        } catch {
            #if DEBUG
            print("ThumbOptimisticWriteFAILED: \(error)")
            #endif
        }
    }

    private func generateThumbFromPending(itemId: String) async -> Bool {
        let summary: SessionRepository.SessionItemSummary? = await MainActor.run {
            try? SessionRepository.shared.sessionItemSummary(itemId: itemId)
        }

        if let summary,
           summary.thumbnailState == .ready,
           let rel = summary.thumbCacheRelPath,
           let url = try? ThumbCacheStore.shared.fullURL(forRelativePath: rel),
           isRealThumb(relPath: rel, url: url) {
            return true
        }

        let pendingRel: String? = await MainActor.run {
            try? SessionRepository.shared.sessionItemPendingFileRelPath(itemId: itemId)
        }
        let resolvedPendingRel = pendingRel ?? findExistingPendingRelPath(itemId: itemId)

        if let resolvedPendingRel, pendingRel == nil {
            await MainActor.run {
                do {
                    try SessionRepository.shared.updatePendingFileRelPath(itemId: itemId, relPath: resolvedPendingRel)
                } catch {
                    #if DEBUG
                    print("ThumbPendingRelBackfillFAILED: \(error)")
                    #endif
                }
            }
        }

        guard let pendingRelPath = resolvedPendingRel,
              let pendingURL = try? PendingFileStore.shared.fullURL(forRelativePath: pendingRelPath),
              FileManager.default.fileExists(atPath: pendingURL.path)
        else {
            return false
        }

        if !isPendingFileSizeSufficient(url: pendingURL) {
            return false
        }

        guard let cgImage = createThumbnailCGImage(from: pendingURL) else {
            return false
        }

        guard let square = makeSquareImage(from: cgImage, size: thumbFilmstripPx),
              let jpegData = encodeJPEG(image: square, quality: thumbJpegQuality) else {
            return false
        }

        let rel = ThumbCacheStore.shared.makeRelativePath(itemId: itemId, fileExtension: "jpg")

        do {
            if let oldRel = summary?.thumbCacheRelPath, oldRel != rel {
                _ = try? ThumbCacheStore.shared.delete(relativePath: oldRel)
            }

            _ = try ThumbCacheStore.shared.writeAtomic(data: jpegData, toRelativePath: rel)

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
            return true
        } catch {
            #if DEBUG
            print("ThumbGenerateFAILED: \(error)")
            #endif
            return false
        }
    }

    private func findExistingPendingRelPath(itemId: String) -> String? {
        let exts = ["heic", "jpg", "jpeg", "png"]
        for ext in exts {
            let rel = PendingFileStore.shared.makeRelativePath(itemId: itemId, fileExtension: ext)
            if PendingFileStore.shared.fileExists(relativePath: rel) {
                return rel
            }
        }
        return nil
    }

    private func isPendingFileSizeSufficient(url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
              let size = values.fileSize else {
            return false
        }
        return size >= pendingMinBytes
    }

    private func createThumbnailCGImage(from url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: max(thumbFilmstripPx, 256),
            kCGImageSourceCreateThumbnailWithTransform: true
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    private func makeSquareImage(from image: CGImage, size: Int) -> CGImage? {
        let width = image.width
        let height = image.height
        let side = min(width, height)
        let originX = (width - side) / 2
        let originY = (height - side) / 2
        let cropRect = CGRect(x: originX, y: originY, width: side, height: side)

        guard let cropped = image.cropping(to: cropRect) else { return nil }
        if side == size { return cropped }

        guard let ctx = CGContext(
            data: nil,
            width: size,
            height: size,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        ctx.interpolationQuality = .high
        ctx.draw(cropped, in: CGRect(x: 0, y: 0, width: size, height: size))
        return ctx.makeImage()
    }

    private func encodeJPEG(image: CGImage, quality: Double) -> Data? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            data,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            return nil
        }

        let options: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: quality
        ]
        CGImageDestinationAddImage(dest, image, options as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return data as Data
    }

    private func isRealThumb(relPath: String, url: URL) -> Bool {
        let lower = relPath.lowercased()
        if !(lower.hasSuffix(".jpg") || lower.hasSuffix(".jpeg")) {
            return false
        }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return false }
        return CGImageSourceCreateImageAtIndex(source, 0, nil) != nil
    }
}
