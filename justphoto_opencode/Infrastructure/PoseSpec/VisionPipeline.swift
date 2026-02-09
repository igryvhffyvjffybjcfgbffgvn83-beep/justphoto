import Foundation
import Combine
import CoreGraphics
import ImageIO
import Vision

// M6.8: Run Vision requests on preview frames to produce landmarks + confidences.

struct VisionLandmark: Sendable {
    // PoseSpec canonical space: portrait-normalized, Y-Down (origin top-left).
    let pPortrait: CGPoint
    let confidence: Float

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

    func process(pixelBuffer: CVPixelBuffer, orientation: CGImagePropertyOrientation) async -> VisionFrameResult? {
        if isProcessing {
            return nil
        }
        isProcessing = true
        defer { isProcessing = false }

        do {
            try sequenceHandler.perform([poseRequest, faceRequest], on: pixelBuffer, orientation: orientation)
        } catch {
            #if DEBUG
            print("VisionPipelinePerformFAILED: \(error)")
            #endif
            return VisionFrameResult(pose: nil, face: nil)
        }

        let pose = parsePose(orientation: orientation)
        let face = parseFace(orientation: orientation)
        return VisionFrameResult(pose: pose, face: face)
    }

    private func parsePose(orientation: CGImagePropertyOrientation) -> VisionPoseResult? {
        guard let results = poseRequest.results, !results.isEmpty else {
            return nil
        }

        // Use the first observation (Vision typically sorts by confidence).
        let obs = results[0]
        guard let all = try? obs.recognizedPoints(.all) else {
            return nil
        }

        var out: [String: VisionLandmark] = [:]

        // Map all recognized joints to canonical keys.
        for (jointKey, rp) in all {
            guard rp.confidence > 0 else { continue }
            let jointName = String(describing: jointKey)
            let key = "body." + jointName
            let p = PoseSpecCoordinateNormalizer.normalize(rp.location, sourceOrientation: orientation)
            out[key] = VisionLandmark(pPortrait: p, confidence: rp.confidence, precisionEstimatesPerPoint: nil)
        }

        // Minimal required keys for later steps.
        let core = [
            "body.leftShoulder",
            "body.rightShoulder",
            "body.leftHip",
            "body.rightHip",
        ]

        if core.allSatisfy({ out[$0] == nil }) {
            return nil
        }

        return VisionPoseResult(points: out)
    }

    private func parseFace(orientation: CGImagePropertyOrientation) -> VisionFaceResult? {
        guard let results = faceRequest.results, !results.isEmpty else {
            return nil
        }

        // Use the first face.
        let face = results[0]
        guard let landmarks = face.landmarks else {
            return nil
        }

        let bboxImage = face.boundingBox
        let bboxPortrait = PoseSpecCoordinateNormalizer.normalizeRect(bboxImage, sourceOrientation: orientation)

        let faceConf = face.confidence

        // VNFaceLandmarks2D points are normalized in the face bounding box coordinate space.
        // Convert them to image-normalized coordinates before applying portrait normalization.
        let lEyeLocal = Self.center(of: landmarks.leftEye)
        let rEyeLocal = Self.center(of: landmarks.rightEye)
        let noseLocal = Self.center(of: landmarks.nose)

        // M6 Phase B2: Use Vision precision estimates for eye landmark filtering.
        let lEyePrecisions = Self.precisionEstimates(of: landmarks.leftEye)
        let rEyePrecisions = Self.precisionEstimates(of: landmarks.rightEye)

        func toImageNormalized(_ local: CGPoint) -> CGPoint {
            CGPoint(
                x: bboxImage.origin.x + local.x * bboxImage.width,
                y: bboxImage.origin.y + local.y * bboxImage.height
            )
        }

        func mkImagePoint(_ pImage: CGPoint?, confidence: Float, precisions: [Float]?) -> VisionLandmark? {
            guard let pImage else { return nil }
            let pp = PoseSpecCoordinateNormalizer.normalize(pImage, sourceOrientation: orientation)
            return VisionLandmark(pPortrait: pp, confidence: confidence, precisionEstimatesPerPoint: precisions)
        }

        // Phase B2: VNFaceObservation provides a single face confidence, not per-landmark.
        // Using faceConf as an eye landmark confidence is too aggressive and can incorrectly drop eye ROIs.
        // We rely on precision estimates to decide if an individual eye is trustworthy.
        let lEye: VisionLandmark? = mkImagePoint(lEyeLocal.map(toImageNormalized), confidence: 1.0, precisions: lEyePrecisions)
        let rEye: VisionLandmark? = mkImagePoint(rEyeLocal.map(toImageNormalized), confidence: 1.0, precisions: rEyePrecisions)

        let n: VisionLandmark? = {
            if let np = noseLocal {
                return mkImagePoint(toImageNormalized(np), confidence: faceConf, precisions: nil)
            }
            return nil
        }()

        // Require at least one stable feature so "cover face" can turn this false.
        if lEye == nil && rEye == nil && n == nil {
            return nil
        }

        return VisionFaceResult(
            faceBBoxPortrait: bboxPortrait,
            leftEyeCenter: lEye,
            rightEyeCenter: rEye,
            noseCenter: n,
            faceConfidence: faceConf
        )
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

    // M6.8: Coordinate normalization is centralized in PoseSpecCoordinateNormalizer.
}

@MainActor
final class VisionPipelineController: ObservableObject {
    @Published private(set) var poseDetected: Bool = false
    @Published private(set) var faceDetected: Bool = false
    @Published private(set) var lastUpdateTsMs: Int = 0

    @Published private(set) var lastPosePointCount: Int = 0
    @Published private(set) var lastFaceConfidence: Float = 0

    @Published private(set) var lastPose: VisionPoseResult? = nil
    @Published private(set) var lastFace: VisionFaceResult? = nil

    private var lastConsolePrintTsMs: Int = 0

    func offer(pixelBuffer: CVPixelBuffer, orientation: CGImagePropertyOrientation) {
        Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            guard let r = await VisionPipeline.shared.process(pixelBuffer: pixelBuffer, orientation: orientation) else {
                return
            }

            let tsMs = Int(Date().timeIntervalSince1970 * 1000)
            await MainActor.run {
                self.poseDetected = r.poseDetected
                self.faceDetected = r.faceDetected
                self.lastUpdateTsMs = tsMs
                self.lastPosePointCount = r.pose?.points.count ?? 0
                self.lastFaceConfidence = r.face?.faceConfidence ?? 0

                self.lastPose = r.pose
                self.lastFace = r.face

                #if DEBUG
                if tsMs - self.lastConsolePrintTsMs >= 1000 {
                    self.lastConsolePrintTsMs = tsMs
                    let faceConfStr = String(format: "%.2f", self.lastFaceConfidence)
                    print("VisionState: poseDetected=\(self.poseDetected) faceDetected=\(self.faceDetected) posePoints=\(self.lastPosePointCount) faceConf=\(faceConfStr)")
                }
                #endif
            }
        }
    }
}
