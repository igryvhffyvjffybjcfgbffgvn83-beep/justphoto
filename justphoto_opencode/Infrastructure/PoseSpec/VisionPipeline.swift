import Foundation
import Combine
import CoreGraphics
import ImageIO
import Vision

// M6.8: Run Vision requests on preview frames to produce landmarks + confidences.

struct VisionLandmark: Sendable {
    let pPortrait: CGPoint
    let confidence: Float
}

struct VisionPoseResult: Sendable {
    // Canonical keys that match PoseSpec binding paths (e.g. body.leftShoulder).
    let points: [String: VisionLandmark]
}

struct VisionFaceResult: Sendable {
    // Portrait-normalized face bounding box.
    let faceBBoxPortrait: CGRect

    // Portrait-normalized feature centers.
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
            let p = Self.toPortraitNormalized(rp.location, sourceOrientation: orientation)
            out[key] = VisionLandmark(pPortrait: p, confidence: rp.confidence)
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
        let bboxPortrait = Self.normalizeRectToPortrait(bboxImage, sourceOrientation: orientation)

        let c = face.confidence

        // VNFaceLandmarks2D points are normalized in the face bounding box coordinate space.
        // Convert them to image-normalized coordinates before applying portrait normalization.
        let lEyeLocal = Self.centerAndOpenness(of: landmarks.leftEye)
        let rEyeLocal = Self.centerAndOpenness(of: landmarks.rightEye)
        let noseLocal = Self.centerAndOpenness(of: landmarks.nose)

        func toImageNormalized(_ local: CGPoint) -> CGPoint {
            CGPoint(
                x: bboxImage.origin.x + local.x * bboxImage.width,
                y: bboxImage.origin.y + local.y * bboxImage.height
            )
        }

        func mkImagePoint(_ pImage: CGPoint?, confidence: Float) -> VisionLandmark? {
            guard let pImage else { return nil }
            let pp = Self.toPortraitNormalized(pImage, sourceOrientation: orientation)
            return VisionLandmark(pPortrait: pp, confidence: confidence)
        }

        // Eye-closed heuristic: if eye landmark is present but vertically collapsed, treat as unavailable.
        let eyeOpenThreshold: CGFloat = 0.12

        let lEye: VisionLandmark?
        if let lp = lEyeLocal.center, let openness = lEyeLocal.openness, openness >= eyeOpenThreshold {
            lEye = mkImagePoint(toImageNormalized(lp), confidence: c)
        } else {
            lEye = nil
        }

        let rEye: VisionLandmark?
        if let rp = rEyeLocal.center, let openness = rEyeLocal.openness, openness >= eyeOpenThreshold {
            rEye = mkImagePoint(toImageNormalized(rp), confidence: c)
        } else {
            rEye = nil
        }

        let n: VisionLandmark? = {
            if let np = noseLocal.center {
                return mkImagePoint(toImageNormalized(np), confidence: c)
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
            faceConfidence: c
        )
    }

    private struct RegionSummary {
        let center: CGPoint?
        // Vertical span / horizontal span; smaller => more closed.
        let openness: CGFloat?
    }

    private static func centerAndOpenness(of region: VNFaceLandmarkRegion2D?) -> RegionSummary {
        guard let region else { return RegionSummary(center: nil, openness: nil) }
        let pts = region.normalizedPoints
        guard !pts.isEmpty else { return RegionSummary(center: nil, openness: nil) }

        var sx: CGFloat = 0
        var sy: CGFloat = 0
        var minX: CGFloat = .greatestFiniteMagnitude
        var maxX: CGFloat = -.greatestFiniteMagnitude
        var minY: CGFloat = .greatestFiniteMagnitude
        var maxY: CGFloat = -.greatestFiniteMagnitude

        for p in pts {
            sx += p.x
            sy += p.y
            minX = min(minX, p.x)
            maxX = max(maxX, p.x)
            minY = min(minY, p.y)
            maxY = max(maxY, p.y)
        }

        let cx = sx / CGFloat(pts.count)
        let cy = sy / CGFloat(pts.count)

        let w = max(0, maxX - minX)
        let h = max(0, maxY - minY)
        let openness: CGFloat?
        if w <= 0.0001 {
            openness = nil
        } else {
            openness = h / w
        }

        return RegionSummary(center: CGPoint(x: cx, y: cy), openness: openness)
    }

    private static func normalizeRectToPortrait(_ r: CGRect, sourceOrientation: CGImagePropertyOrientation) -> CGRect {
        let corners = [
            CGPoint(x: r.minX, y: r.minY),
            CGPoint(x: r.maxX, y: r.minY),
            CGPoint(x: r.minX, y: r.maxY),
            CGPoint(x: r.maxX, y: r.maxY),
        ]
        let pts = corners.map { toPortraitNormalized($0, sourceOrientation: sourceOrientation) }

        let xs = pts.map { $0.x }
        let ys = pts.map { $0.y }
        guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() else {
            return .zero
        }
        return CGRect(
            x: minX,
            y: minY,
            width: max(CGFloat(0), maxX - minX),
            height: max(CGFloat(0), maxY - minY)
        )
    }

    // Keep the normalization logic local so M6.8 doesn't depend on other files.
    private static func toPortraitNormalized(_ p: CGPoint, sourceOrientation: CGImagePropertyOrientation) -> CGPoint {
        let x = p.x
        let y = p.y

        switch sourceOrientation {
        case .up:
            return CGPoint(x: x, y: y)
        case .down:
            return CGPoint(x: 1 - x, y: 1 - y)
        case .left:
            return CGPoint(x: y, y: 1 - x)
        case .right:
            return CGPoint(x: 1 - y, y: x)

        case .upMirrored:
            return CGPoint(x: 1 - x, y: y)
        case .downMirrored:
            return CGPoint(x: x, y: 1 - y)
        case .leftMirrored:
            return CGPoint(x: 1 - y, y: 1 - x)
        case .rightMirrored:
            return CGPoint(x: y, y: x)

        @unknown default:
            return CGPoint(x: x, y: y)
        }
    }
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
