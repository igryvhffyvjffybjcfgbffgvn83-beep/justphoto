import Foundation
import CoreVideo
import ImageIO
import Vision

// M6.10 Phase 1: MetricComputer scaffold.
// This milestone intentionally does NOT implement any math.

struct MetricContext {
    let pose: VisionPoseResult?
    let face: VisionFaceResult?
    let rois: ROISet?
    let pixelBuffer: CVPixelBuffer?
    let orientation: CGImagePropertyOrientation?
}

final class MetricComputer {
    static let shared = MetricComputer()

    private let poseNormalizer = PoseLandmarkNormalizer()
    private var cachedMinLandmarkConfidence: Float? = nil

    private init() {
        print("MetricContract loaded: T0_Count=\(MetricContractBook.t0Count) T1_Count=\(MetricContractBook.t1Count)")
    }

    func computeMetrics(context: MetricContext) -> [MetricKey: Double] {
        #if DEBUG
        dumpPoseLandmarksIfPossible(context: context)
        #endif
        return [:]
    }

    #if DEBUG
    private func dumpPoseLandmarksIfPossible(context: MetricContext) {
        guard let minConf = loadMinLandmarkConfidence() else {
            return
        }

        guard let obs = context.pose?.rawObservation?.observation else {
            let thr = String(format: "%.2f", minConf)
            print("PoseSpecLandmarksDump: (no_pose)")
            print("BodyPointsStats: Total=0 Filtered=0 Threshold=\(thr)")
            return
        }

        let (points, stats) = poseNormalizer.normalizeWithStats(observation: obs, minConfidence: minConf)

        // Dump a PoseSpec-like alias view for quick console verification.
        var parts: [String] = []
        for j in LandmarkBindings.orderedBodyJoints {
            guard let alias = LandmarkBindings.bodyJointToDebugAlias[j] else { continue }
            guard let key = LandmarkBindings.bodyJointToCanonicalKey[j] else { continue }
            guard let bp = points[key] else { continue }

            let x = Double(bp.pPortrait.x)
            let y = Double(bp.pPortrait.y)
            let c = Double(bp.confidence)
            parts.append(
                "\(alias.rawValue)=(\(String(format: "%.3f", x)), \(String(format: "%.3f", y))) conf=\(String(format: "%.2f", c))"
            )
        }

        if parts.isEmpty {
            print("PoseSpecLandmarksDump: (empty)")
        } else {
            print("PoseSpecLandmarksDump: \(parts.joined(separator: ", "))")
        }

        let thr = String(format: "%.2f", Double(stats.threshold))
        print("BodyPointsStats: Total=\(stats.totalCandidates) Filtered=\(stats.filtered) Threshold=\(thr)")
    }

    private func loadMinLandmarkConfidence() -> Float? {
        if let v = cachedMinLandmarkConfidence {
            return v
        }
        guard let spec = try? PoseSpecLoader.shared.loadPoseSpec() else {
            return nil
        }
        let v = Float(spec.defaults.confidence.minLandmarkConfidence)
        cachedMinLandmarkConfidence = v
        return v
    }
    #endif
}
