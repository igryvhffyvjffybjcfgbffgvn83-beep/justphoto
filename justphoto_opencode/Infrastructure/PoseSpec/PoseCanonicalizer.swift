import CoreGraphics
import Foundation
import ImageIO
import Vision

// Single source of truth for pose coordinate canonicalization.
//
// Contract:
// - Input: Vision raw joint points + frame orientation.
// - Output: PoseSpec canonical points (portrait, y-down, normalized in [0,1]).
// - Reject rule: low confidence / invalid / out-of-range points are dropped.
enum PosePointDropReason: String, Sendable {
    case lowConf = "low_conf"
    case outOfRange = "out_of_range"
    case missingInput = "missing_input"
}

struct PoseCanonicalizationStats: Sendable {
    let totalCandidates: Int
    let kept: Int
    let threshold: Float

    var dropped: Int { max(0, totalCandidates - kept) }
}

struct PoseCanonicalizationResult: Sendable {
    let points: [String: VisionLandmark]
    let droppedReasonsByJointKey: [String: PosePointDropReason]
    let stats: PoseCanonicalizationStats
}

enum PoseCanonicalizer {
    private static let cacheLock = NSLock()
    private static var cachedMinLandmarkConfidence: Float? = nil
    private static let fallbackMinLandmarkConfidence: Float = 0.5

    static func canonicalize(
        observation: VNHumanBodyPoseObservation,
        orientation: CGImagePropertyOrientation
    ) -> PoseCanonicalizationResult {
        let minConfidence = resolveMinLandmarkConfidence()
        return canonicalize(
            observation: observation,
            orientation: orientation,
            minConfidence: minConfidence
        )
    }

    static func canonicalize(
        observation: VNHumanBodyPoseObservation,
        orientation: CGImagePropertyOrientation,
        minConfidence: Float
    ) -> PoseCanonicalizationResult {
        let clampedMinConfidence = max(0.0, min(1.0, minConfidence))
        var points: [String: VisionLandmark] = [:]
        var dropped: [String: PosePointDropReason] = [:]
        var totalCandidates = 0

        for joint in LandmarkBindings.orderedBodyJoints {
            guard let key = LandmarkBindings.bodyJointToCanonicalKey[joint] else { continue }
            guard let recognized = try? observation.recognizedPoint(joint) else {
                dropped[key] = .missingInput
                continue
            }

            totalCandidates += 1

            let conf = recognized.confidence
            guard conf.isFinite, conf >= clampedMinConfidence else {
                dropped[key] = .lowConf
                continue
            }

            guard let canonical = canonicalPoint(recognized.location, orientation: orientation) else {
                dropped[key] = .outOfRange
                continue
            }

            // Hard contract: all emitted canonical points must be in [0,1] x [0,1].
            assert(
                canonical.x >= 0.0 && canonical.x <= 1.0 &&
                    canonical.y >= 0.0 && canonical.y <= 1.0
            )

            points[key] = VisionLandmark(
                pPortrait: canonical,
                confidence: conf,
                aspectRatioHeightOverWidth: nil,
                precisionEstimatesPerPoint: nil
            )
        }

        return PoseCanonicalizationResult(
            points: points,
            droppedReasonsByJointKey: dropped,
            stats: PoseCanonicalizationStats(
                totalCandidates: totalCandidates,
                kept: points.count,
                threshold: clampedMinConfidence
            )
        )
    }

    private static func canonicalPoint(
        _ raw: CGPoint,
        orientation: CGImagePropertyOrientation
    ) -> CGPoint? {
        guard raw.x.isFinite, raw.y.isFinite else {
            return nil
        }
        guard raw.x >= 0.0, raw.x <= 1.0, raw.y >= 0.0, raw.y <= 1.0 else {
            return nil
        }

        // Vision receives orientation at request-time; it already reports oriented normalized points.
        // Canonicalization here only converts Y-up to Y-down.
        _ = orientation
        let canonical = CGPoint(x: raw.x, y: 1.0 - raw.y)
        guard canonical.x >= 0.0, canonical.x <= 1.0, canonical.y >= 0.0, canonical.y <= 1.0 else {
            return nil
        }
        return canonical
    }

    private static func resolveMinLandmarkConfidence() -> Float {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        if let cached = cachedMinLandmarkConfidence {
            return cached
        }
        let resolved: Float
        if let spec = try? PoseSpecLoader.shared.loadPoseSpec() {
            let value = Float(spec.defaults.confidence.minLandmarkConfidence)
            if value.isFinite {
                resolved = max(0.0, min(1.0, value))
            } else {
                resolved = fallbackMinLandmarkConfidence
            }
        } else {
            resolved = fallbackMinLandmarkConfidence
        }
        cachedMinLandmarkConfidence = resolved
        return resolved
    }
}
