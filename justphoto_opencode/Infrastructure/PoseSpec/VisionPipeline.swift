import Foundation
import Combine
import CoreGraphics
import ImageIO
import Vision
import CoreVideo

// M6.8: Run Vision requests on preview frames to produce landmarks + confidences.

struct VisionLandmark: Sendable {
    // PoseSpec canonical space: portrait-normalized, Y-Down (origin top-left).
    let pPortrait: CGPoint
    // `confidence` is only set when Vision provides a true confidence for the landmark.
    // For face landmarks, Vision does not provide per-landmark confidence; keep this nil.
    let confidence: Float?

    // M6.9.1: Eye open/close geometry hint.
    // Computed from Vision's raw landmark point cloud (face-local normalized space).
    // Defined as (height / width) of the landmark's bounding box; smaller usually means blinking/closed.
    let aspectRatioHeightOverWidth: Float?

    // M6 Phase B2: Vision per-landmark precision estimates.
    // Only populated for face landmarks (e.g. eyes); nil for pose joints.
    let precisionEstimatesPerPoint: [Float]?

    var precisionEstimate0: Float? {
        precisionEstimatesPerPoint?.first
    }
}

struct VisionPoseResult: Sendable {
    // Canonical keys that match PoseSpec binding paths (e.g. body.leftShoulder).
    let points: [String: VisionLandmark]

    // Phase 1: Preserve the raw observation for MetricComputer's normalization adapter.
    // This is wrapped as @unchecked Sendable so we can pass it through Task.detached boundaries.
    let rawObservation: UncheckedSendablePoseObservation?
}

struct UncheckedSendablePoseObservation: @unchecked Sendable {
    let observation: VNHumanBodyPoseObservation
}

struct VisionFaceResult: Sendable {
    // PoseSpec canonical space: portrait-normalized, Y-Down (origin top-left).
    let faceBBoxPortrait: CGRect

    // PoseSpec canonical space: portrait-normalized, Y-Down (origin top-left).
    let leftEyeCenter: VisionLandmark?
    let rightEyeCenter: VisionLandmark?
    let noseCenter: VisionLandmark?
    let faceConfidence: Float
}

struct VisionFrameResult: Sendable {
    let pose: VisionPoseResult?
    let face: VisionFaceResult?

    var poseDetected: Bool { pose != nil }
    var faceDetected: Bool { face != nil }
}

actor VisionPipeline {
    static let shared = VisionPipeline()

    private let sequenceHandler = VNSequenceRequestHandler()
    private let poseRequest = VNDetectHumanBodyPoseRequest()
    private let faceRequest = VNDetectFaceLandmarksRequest()

    private var isProcessing: Bool = false

    // M6.8 Hotfix: observability + data-flow diagnostics.
    private var lastDebugPrintTsMs: Int = 0
    private var droppedFramesSinceLastPrint: Int = 0

    func process(pixelBuffer: CVPixelBuffer, orientation: CGImagePropertyOrientation) async -> VisionFrameResult? {
        if isProcessing {
            droppedFramesSinceLastPrint += 1
            return nil
        }
        isProcessing = true
        defer { isProcessing = false }

        let tsMs = Int(Date().timeIntervalSince1970 * 1000)
        let shouldPrint = (tsMs - lastDebugPrintTsMs) >= 1000

        do {
            try sequenceHandler.perform([poseRequest, faceRequest], on: pixelBuffer, orientation: orientation)
        } catch {
            #if DEBUG
            if shouldPrint {
                print("DEBUG_PIPELINE: perform_failed o=\(orientation.rawValue) err=\(error)")
            }
            #endif
            return VisionFrameResult(pose: nil, face: nil)
        }

        let bodyCount = poseRequest.results?.count ?? 0
        let faceCount = faceRequest.results?.count ?? 0

        let pose = parsePose(orientation: orientation, debugEnabled: shouldPrint)
        let face = parseFace(orientation: orientation, debugEnabled: shouldPrint)

        #if DEBUG
        if shouldPrint {
            lastDebugPrintTsMs = tsMs

            let w = CVPixelBufferGetWidth(pixelBuffer)
            let h = CVPixelBufferGetHeight(pixelBuffer)
            let fmt = CVPixelBufferGetPixelFormatType(pixelBuffer)
            let joints = pose?.points.count ?? 0
            let dropped = droppedFramesSinceLastPrint
            droppedFramesSinceLastPrint = 0

            print(
                "DEBUG_PIPELINE: O=\(orientation.rawValue) | W=\(w) H=\(h) FMT=\(Self.fourCC(fmt))(\(fmt)) | Body=\(bodyCount) | Face=\(faceCount) | pose=\(pose != nil) face=\(face != nil) | Joints=\(joints) | Dropped=\(dropped)"
            )
        }
        #endif
        return VisionFrameResult(pose: pose, face: face)
    }

    // M6.8 Hotfix (Relax Logic): if Vision produced an observation, return a non-nil pose.
    // Do NOT discard the entire pose due to confidence thresholds or missing core joints.
    private func parsePose(orientation: CGImagePropertyOrientation, debugEnabled: Bool) -> VisionPoseResult? {
        guard let results = poseRequest.results, !results.isEmpty else {
            return nil
        }

        // Use the first observation (Vision typically sorts by confidence).
        let obs = results[0]
        let all: [VNHumanBodyPoseObservation.JointName: VNRecognizedPoint]
        do {
            all = try obs.recognizedPoints(.all)
        } catch {
            #if DEBUG
            if debugEnabled {
                print("DEBUG_PIPELINE: pose_recognizedPoints_failed err=\(error)")
            }
            #endif
            return VisionPoseResult(points: [:], rawObservation: nil)
        }

        var out: [String: VisionLandmark] = [:]

        var confPosCount = 0
        var maxConf: Float = 0

        // Map all recognized joints to canonical keys.
        for (jointKey, rp) in all {
            if rp.confidence > 0 { confPosCount += 1 }
            if rp.confidence > maxConf { maxConf = rp.confidence }
            let key = "body." + String(describing: jointKey)
            let p = PoseSpecCoordinateNormalizer.shared.normalize(rp.location, sourceOrientation: orientation)
            out[key] = VisionLandmark(pPortrait: p, confidence: rp.confidence, aspectRatioHeightOverWidth: nil, precisionEstimatesPerPoint: nil)
        }

        #if DEBUG
        if debugEnabled {
            print("DEBUG_PIPELINE: pose_obs0 joints_total=\(all.count) conf>0=\(confPosCount) maxConf=\(String(format: "%.2f", maxConf))")

            // Print a small, stable subset of joints for quick sanity.
            let coreKeys: [(VNHumanBodyPoseObservation.JointName, String)] = [
                (.nose, "nose"),
                (.neck, "neck"),
                (.leftShoulder, "leftShoulder"),
                (.rightShoulder, "rightShoulder"),
                (.leftHip, "leftHip"),
                (.rightHip, "rightHip"),
            ]
            for (jn, name) in coreKeys {
                if let rp = all[jn] {
                    print("DEBUG_PIPELINE: pose_joint \(name) conf=\(String(format: "%.2f", rp.confidence)) loc=\(rp.location)")
                } else {
                    print("DEBUG_PIPELINE: pose_joint \(name) missing")
                }
            }
        }
        #endif

        return VisionPoseResult(points: out, rawObservation: UncheckedSendablePoseObservation(observation: obs))
    }

    // M6.8 Hotfix (Relax Logic): if Vision produced a face observation, return a non-nil face.
    // Do NOT discard face due to missing landmarks or feature extraction failures.
    private func parseFace(orientation: CGImagePropertyOrientation, debugEnabled: Bool) -> VisionFaceResult? {
        guard let results = faceRequest.results, !results.isEmpty else {
            return nil
        }

        // Use the first face.
        let face = results[0]
        let bboxImage = face.boundingBox
        let bboxPortrait = PoseSpecCoordinateNormalizer.shared.normalizeRect(bboxImage, sourceOrientation: orientation)
        let faceConf = face.confidence

        guard let landmarks = face.landmarks else {
            #if DEBUG
            if debugEnabled {
                print("DEBUG_PIPELINE: face_landmarks_missing conf=\(String(format: "%.2f", faceConf)) bbox=\(bboxImage)")
            }
            #endif

            return VisionFaceResult(
                faceBBoxPortrait: bboxPortrait,
                leftEyeCenter: nil,
                rightEyeCenter: nil,
                noseCenter: nil,
                faceConfidence: faceConf
            )
        }

        // VNFaceLandmarks2D points are normalized in the face bounding box coordinate space.
        // Convert them to image-normalized coordinates before applying portrait normalization.
        let lEyeLocal = Self.center(of: landmarks.leftEye)
        let rEyeLocal = Self.center(of: landmarks.rightEye)
        let noseLocal = Self.center(of: landmarks.nose)

        // M6 Phase B2: Use Vision precision estimates for eye landmark filtering.
        let lEyePrecisions = Self.precisionEstimates(of: landmarks.leftEye)
        let rEyePrecisions = Self.precisionEstimates(of: landmarks.rightEye)
        let nosePrecisions = Self.precisionEstimates(of: landmarks.nose)

        // M6.9.1: Use landmark bounding-box aspect ratio to detect blinking/closed eyes.
        let lEyeRatio = Self.aspectRatioHeightOverWidth(of: landmarks.leftEye)
        let rEyeRatio = Self.aspectRatioHeightOverWidth(of: landmarks.rightEye)

        func toImageNormalized(_ local: CGPoint) -> CGPoint {
            CGPoint(
                x: bboxImage.origin.x + local.x * bboxImage.width,
                y: bboxImage.origin.y + local.y * bboxImage.height
            )
        }

        func mkImagePoint(_ pImage: CGPoint?, confidence: Float?, ratioHW: Float?, precisions: [Float]?) -> VisionLandmark? {
            guard let pImage else { return nil }
            let pp = PoseSpecCoordinateNormalizer.shared.normalize(pImage, sourceOrientation: orientation)
            return VisionLandmark(pPortrait: pp, confidence: confidence, aspectRatioHeightOverWidth: ratioHW, precisionEstimatesPerPoint: precisions)
        }

        // Phase B2: VNFaceObservation provides a single face confidence, not per-landmark.
        // Do not "borrow" it for landmarks; leave landmark confidence nil and rely on precision estimates.
        let lEye: VisionLandmark? = mkImagePoint(lEyeLocal.map(toImageNormalized), confidence: nil, ratioHW: lEyeRatio, precisions: lEyePrecisions)
        let rEye: VisionLandmark? = mkImagePoint(rEyeLocal.map(toImageNormalized), confidence: nil, ratioHW: rEyeRatio, precisions: rEyePrecisions)

        let n: VisionLandmark? = {
            if let np = noseLocal {
                return mkImagePoint(toImageNormalized(np), confidence: nil, ratioHW: nil, precisions: nosePrecisions)
            }
            return nil
        }()

        #if DEBUG
        if debugEnabled {
            let l = (lEye != nil) ? "1" : "0"
            let r = (rEye != nil) ? "1" : "0"
            let nn = (n != nil) ? "1" : "0"
            print("DEBUG_PIPELINE: face_obs0 conf=\(String(format: "%.2f", faceConf)) features lEye=\(l) rEye=\(r) nose=\(nn)")
        }
        #endif

        return VisionFaceResult(
            faceBBoxPortrait: bboxPortrait,
            leftEyeCenter: lEye,
            rightEyeCenter: rEye,
            noseCenter: n,
            faceConfidence: faceConf
        )
    }

    private static func fourCC(_ v: OSType) -> String {
        let a = Character(UnicodeScalar((v >> 24) & 0xff)!)
        let b = Character(UnicodeScalar((v >> 16) & 0xff)!)
        let c = Character(UnicodeScalar((v >> 8) & 0xff)!)
        let d = Character(UnicodeScalar(v & 0xff)!)
        return String([a, b, c, d])
    }

    private static func center(of region: VNFaceLandmarkRegion2D?) -> CGPoint? {
        guard let region else { return nil }
        let pts = region.normalizedPoints
        guard !pts.isEmpty else { return nil }

        var sx: CGFloat = 0
        var sy: CGFloat = 0
        for p in pts {
            sx += p.x
            sy += p.y
        }

        let cx = sx / CGFloat(pts.count)
        let cy = sy / CGFloat(pts.count)

        return CGPoint(x: cx, y: cy)
    }

    private static func precisionEstimates(of region: VNFaceLandmarkRegion2D?) -> [Float]? {
        guard let region else { return nil }

        // Vision reports per-point precision as NSNumber values.
        guard let estimates = region.precisionEstimatesPerPoint as? [NSNumber], !estimates.isEmpty else {
            return nil
        }
        return estimates.map { $0.floatValue }
    }

    private static func aspectRatioHeightOverWidth(of region: VNFaceLandmarkRegion2D?) -> Float? {
        // Rotation-agnostic eye aspect ratio (EAR): minor_axis / major_axis.
        // Computed via PCA on the landmark point cloud so head tilt won't invert width/height.
        guard let region else { return nil }
        let pts = region.normalizedPoints
        guard pts.count >= 3 else { return nil }

        var mx: Double = 0
        var my: Double = 0
        for p in pts {
            mx += Double(p.x)
            my += Double(p.y)
        }
        let n = Double(pts.count)
        mx /= n
        my /= n

        var cxx: Double = 0
        var cxy: Double = 0
        var cyy: Double = 0
        for p in pts {
            let dx = Double(p.x) - mx
            let dy = Double(p.y) - my
            cxx += dx * dx
            cxy += dx * dy
            cyy += dy * dy
        }
        cxx /= n
        cxy /= n
        cyy /= n

        let trace = cxx + cyy
        let det = (cxx * cyy) - (cxy * cxy)
        let halfTrace = trace * 0.5
        let disc = sqrt(max(0.0, (halfTrace * halfTrace) - det))
        let l1 = halfTrace + disc
        let l2 = halfTrace - disc

        let major = sqrt(max(l1, l2))
        let minor = sqrt(max(0.0, min(l1, l2)))
        guard major > 1e-6 else { return nil }

        let ear = minor / major
        if !ear.isFinite { return nil }
        return Float(max(0.0, min(1.0, ear)))
    }

    // M6.8: Coordinate normalization is centralized in PoseSpecCoordinateNormalizer.
}

final class TierScheduler: ObservableObject {
    @Published private(set) var poseDetected: Bool = false
    @Published private(set) var faceDetected: Bool = false
    @Published private(set) var lastUpdateTsMs: Int = 0

    @Published private(set) var lastPosePointCount: Int = 0
    @Published private(set) var lastFaceConfidence: Float = 0

    @Published private(set) var lastPose: VisionPoseResult? = nil
    @Published private(set) var lastFace: VisionFaceResult? = nil

    private struct FramePacket {
        let pixelBuffer: CVPixelBuffer
        let orientation: CGImagePropertyOrientation
    }

    private final class InFlightGate {
        private let lock = NSLock()
        private var inFlight: Bool = false

        func tryEnter() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            if inFlight { return false }
            inFlight = true
            return true
        }

        func exit() {
            lock.lock()
            inFlight = false
            lock.unlock()
        }
    }

    private let latestFrameLock = NSLock()
    private var latestFrame: FramePacket? = nil

    private let latestVisionLock = NSLock()
    private var latestPoseSnapshot: VisionPoseResult? = nil
    private var latestFaceSnapshot: VisionFaceResult? = nil

    private let t0Gate = InFlightGate()
    private let t1Gate = InFlightGate()

    private let t0Queue = DispatchQueue(label: "justphoto.tier.t0_queue", qos: .userInitiated)
    private let t1Queue = DispatchQueue(label: "justphoto.tier.t1_queue", qos: .utility)
    private let t0TimerQueue = DispatchQueue(label: "justphoto.tier.t0_timer", qos: .utility)
    private let t1TimerQueue = DispatchQueue(label: "justphoto.tier.t1_timer", qos: .utility)

    private var t0Timer: DispatchSourceTimer? = nil
    private var t1Timer: DispatchSourceTimer? = nil

    private var lastConsolePrintTsMs: Int = 0

    #if DEBUG
    private let debugLock = NSLock()
    private var debugLastPrintTsMs: Int = 0
    private var debugT0Ticks: Int = 0
    private var debugT1Ticks: Int = 0
    private var debugT0Skipped: Int = 0
    private var debugT1Skipped: Int = 0
    #endif

    init() {
        startTimers()
    }

    func offer(pixelBuffer: CVPixelBuffer, orientation: CGImagePropertyOrientation) {
        let packet = FramePacket(pixelBuffer: pixelBuffer, orientation: orientation)
        latestFrameLock.lock()
        // O(1) overwrite: keep only the latest frame, drop all older frames.
        latestFrame = packet
        latestFrameLock.unlock()
    }

    deinit {
        stopTimers()
    }

    private func startTimers() {
        let t0IntervalNs = Int((1_000_000_000.0 / 15.0).rounded())
        let t1IntervalNs = Int((1_000_000_000.0 / 2.0).rounded())

        let t0 = DispatchSource.makeTimerSource(queue: t0TimerQueue)
        t0.schedule(
            deadline: .now() + .nanoseconds(t0IntervalNs),
            repeating: .nanoseconds(t0IntervalNs),
            leeway: .milliseconds(4)
        )
        t0.setEventHandler { [weak self] in
            self?.handleT0Tick()
        }
        t0.resume()
        t0Timer = t0

        let t1 = DispatchSource.makeTimerSource(queue: t1TimerQueue)
        t1.schedule(
            deadline: .now() + .nanoseconds(t1IntervalNs),
            repeating: .nanoseconds(t1IntervalNs),
            leeway: .milliseconds(8)
        )
        t1.setEventHandler { [weak self] in
            self?.handleT1Tick()
        }
        t1.resume()
        t1Timer = t1
    }

    private func stopTimers() {
        t0Timer?.setEventHandler {}
        t0Timer?.cancel()
        t0Timer = nil

        t1Timer?.setEventHandler {}
        t1Timer?.cancel()
        t1Timer = nil
    }

    private func handleT0Tick() {
        guard let frame = latestFrameSnapshot() else {
            #if DEBUG
            debugRecord(t0Skipped: true)
            #endif
            return
        }
        // In-flight gate: if the previous T0 task is still running, skip this tick.
        guard t0Gate.tryEnter() else {
            #if DEBUG
            debugRecord(t0Skipped: true)
            #endif
            return
        }
        #if DEBUG
        debugRecord(t0Ticked: true)
        #endif

        let gate = t0Gate
        t0Queue.async { [weak self] in
            defer { gate.exit() }
            guard let self else { return }

            // T0: run Vision on the latest frame only.
            let result = self.processVision(frame: frame)
            guard let result else { return }

            self.storeLatestVision(pose: result.pose, face: result.face)
            self.publishVision(result: result)
        }
    }

    private func handleT1Tick() {
        guard let frame = latestFrameSnapshot() else {
            #if DEBUG
            debugRecord(t1Skipped: true)
            #endif
            return
        }
        // In-flight gate: if the previous T1 task is still running, skip this tick.
        guard t1Gate.tryEnter() else {
            #if DEBUG
            debugRecord(t1Skipped: true)
            #endif
            return
        }
        #if DEBUG
        debugRecord(t1Ticked: true)
        #endif

        let gate = t1Gate
        t1Queue.async { [weak self] in
            defer { gate.exit() }
            guard let self else { return }

            // T1: use the most recent Vision outputs + latest frame for frame/ROI metrics.
            let (pose, face) = self.latestVisionSnapshot()
            let rois = ROIComputer.compute(pose: pose, face: face)

            #if DEBUG
            print("DEBUG_T1: Context has buffer? true rois? \((rois != nil) ? "true" : "false")")
            #endif

            _ = MetricComputer.shared.computeMetrics(
                context: MetricContext(
                    pose: pose,
                    face: face,
                    rois: rois,
                    pixelBuffer: frame.pixelBuffer,
                    orientation: frame.orientation
                )
            )
        }
    }

    private func latestFrameSnapshot() -> FramePacket? {
        latestFrameLock.lock()
        defer { latestFrameLock.unlock() }
        return latestFrame
    }

    private func storeLatestVision(pose: VisionPoseResult?, face: VisionFaceResult?) {
        latestVisionLock.lock()
        latestPoseSnapshot = pose
        latestFaceSnapshot = face
        latestVisionLock.unlock()
    }

    private func latestVisionSnapshot() -> (VisionPoseResult?, VisionFaceResult?) {
        latestVisionLock.lock()
        defer { latestVisionLock.unlock() }
        return (latestPoseSnapshot, latestFaceSnapshot)
    }

    private func processVision(frame: FramePacket) -> VisionFrameResult? {
        let semaphore = DispatchSemaphore(value: 0)
        var output: VisionFrameResult? = nil

        // Bridge async Vision pipeline into the serial T0 queue without blocking UI.
        Task {
            output = await VisionPipeline.shared.process(pixelBuffer: frame.pixelBuffer, orientation: frame.orientation)
            semaphore.signal()
        }

        semaphore.wait()
        return output
    }

    private func publishVision(result: VisionFrameResult) {
        let tsMs = nowMs()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.poseDetected = result.poseDetected
            self.faceDetected = result.faceDetected
            self.lastUpdateTsMs = tsMs
            self.lastPosePointCount = result.pose?.points.count ?? 0
            self.lastFaceConfidence = result.face?.faceConfidence ?? 0

            self.lastPose = result.pose
            self.lastFace = result.face

            #if DEBUG
            if tsMs - self.lastConsolePrintTsMs >= 1000 {
                self.lastConsolePrintTsMs = tsMs
                let faceConfStr = String(format: "%.2f", self.lastFaceConfidence)
                print("DEBUG_PIPELINE: VisionState poseDetected=\(self.poseDetected) faceDetected=\(self.faceDetected) posePoints=\(self.lastPosePointCount) faceConf=\(faceConfStr)")
            }
            #endif
        }
    }

    private func nowMs() -> Int {
        Int(Date().timeIntervalSince1970 * 1000)
    }

    #if DEBUG
    private func debugRecord(
        t0Ticked: Bool = false,
        t1Ticked: Bool = false,
        t0Skipped: Bool = false,
        t1Skipped: Bool = false
    ) {
        debugLock.lock()
        if t0Ticked { debugT0Ticks += 1 }
        if t1Ticked { debugT1Ticks += 1 }
        if t0Skipped { debugT0Skipped += 1 }
        if t1Skipped { debugT1Skipped += 1 }

        let now = nowMs()
        if now - debugLastPrintTsMs >= 1000 {
            debugLastPrintTsMs = now
            print(
                "DEBUG_TIER: t0_ticks=\(debugT0Ticks) t1_ticks=\(debugT1Ticks) t0_skipped=\(debugT0Skipped) t1_skipped=\(debugT1Skipped)"
            )
            debugT0Ticks = 0
            debugT1Ticks = 0
            debugT0Skipped = 0
            debugT1Skipped = 0
        }
        debugLock.unlock()
    }
    #endif
}
