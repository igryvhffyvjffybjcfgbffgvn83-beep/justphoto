import CoreGraphics
import Foundation
import Vision

// M6.10 Phase 1: Standardize Vision pose joints into PoseSpec canonical space.
//
// Output contract:
// - keys: PoseSpec canonical joint keys ("body.<joint>")
// - coordinates: normalized [0,1], portrait image space, Y-Down (origin top-left)
// - strict ignore: missing or low-confidence joints are omitted (never emit 0,0 placeholders)

struct BodyPoint: Sendable {
    let pPortrait: CGPoint
    let confidence: Float
}

struct PoseLandmarkNormalizationStats: Sendable {
    let totalCandidates: Int
    let kept: Int
    let threshold: Float

    var dropped: Int { max(0, totalCandidates - kept) }
}

struct PoseLandmarkNormalizer {
    func normalize(observation: VNHumanBodyPoseObservation, minConfidence: Float) -> [String: BodyPoint] {
        normalizeWithStats(observation: observation, minConfidence: minConfidence).points
    }

    func normalizeWithStats(observation: VNHumanBodyPoseObservation, minConfidence: Float) -> (points: [String: BodyPoint], stats: PoseLandmarkNormalizationStats) {
        var out: [String: BodyPoint] = [:]
        var total = 0
        var kept = 0

        for joint in LandmarkBindings.orderedBodyJoints {
            guard let key = LandmarkBindings.bodyJointToCanonicalKey[joint] else {
                continue
            }

            guard let rp = try? observation.recognizedPoint(joint) else {
                continue
            }

            let conf = rp.confidence
            guard conf.isFinite else { continue }

            // Count only joints that Vision actually returned.
            total += 1

            guard conf >= minConfidence else {
                continue
            }

            let loc = rp.location
            guard loc.x.isFinite, loc.y.isFinite else {
                continue
            }

            // Vision joint locations are normalized with origin bottom-left (Y-Up).
            // PoseSpec canonical is Y-Down (origin top-left), so flip Y.
            var x = loc.x
            var y = 1.0 - loc.y

            // Last-line-of-defense clamp (prevents downstream math from going out of unit space).
            x = min(1.0, max(0.0, x))
            y = min(1.0, max(0.0, y))

            let p = CGPoint(x: x, y: y)
            out[key] = BodyPoint(pPortrait: p, confidence: conf)
            kept += 1
        }

        return (out, PoseLandmarkNormalizationStats(totalCandidates: total, kept: kept, threshold: minConfidence))
    }
}
