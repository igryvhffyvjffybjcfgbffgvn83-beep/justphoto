import CoreGraphics
import Foundation

// M6.18: Mirror evaluator (x' = 1 - x) for withRef error comparison.
// Pure functions only: no shared state, no side effects.

struct MirrorEvaluationResult: Sendable {
    let errorValue: Double?
    let mirrorApplied: Bool
}

enum MirrorEvaluator {
    static func mirrorPoint(_ p: CGPoint) -> CGPoint {
        CGPoint(x: 1.0 - p.x, y: p.y)
    }

    static func mirrorRect(_ r: CGRect) -> CGRect {
        CGRect(x: 1.0 - r.maxX, y: r.minY, width: r.width, height: r.height)
    }

    static func mirrorLandmark(_ l: VisionLandmark) -> VisionLandmark {
        VisionLandmark(
            pPortrait: mirrorPoint(l.pPortrait),
            confidence: l.confidence,
            aspectRatioHeightOverWidth: l.aspectRatioHeightOverWidth,
            precisionEstimatesPerPoint: l.precisionEstimatesPerPoint
        )
    }

    static func mirrorPose(_ pose: VisionPoseResult?) -> VisionPoseResult? {
        guard let pose else { return nil }
        var out: [String: VisionLandmark] = [:]
        out.reserveCapacity(pose.points.count)
        for (k, v) in pose.points {
            out[k] = mirrorLandmark(v)
        }
        // Raw observations cannot be mirrored safely; drop them.
        return VisionPoseResult(points: out, rawObservation: nil)
    }

    static func mirrorFace(_ face: VisionFaceResult?) -> VisionFaceResult? {
        guard let face else { return nil }
        return VisionFaceResult(
            faceBBoxPortrait: mirrorRect(face.faceBBoxPortrait),
            leftEyeCenter: face.leftEyeCenter.map(mirrorLandmark),
            rightEyeCenter: face.rightEyeCenter.map(mirrorLandmark),
            noseCenter: face.noseCenter.map(mirrorLandmark),
            faceConfidence: face.faceConfidence
        )
    }

    static func mirrorMetricOutputs(_ metrics: [MetricKey: MetricOutput]) -> [MetricKey: MetricOutput] {
        var out = metrics

        // Swap left/right keyed outputs.
        swap(&out, .colorTempLeftK, .colorTempRightK)

        // Mirror x-dependent scalar outputs.
        out[.centerXOffset] = negate(out[.centerXOffset])
        out[.registrationOffsetX] = negate(out[.registrationOffsetX])
        out[.faceHalfDiff] = negate(out[.faceHalfDiff])

        return out
    }

    static func chooseSmallerError(normal: Double?, mirrored: Double?) -> MirrorEvaluationResult? {
        switch (normal, mirrored) {
        case (nil, nil):
            return nil
        case (let v?, nil):
            return MirrorEvaluationResult(errorValue: v, mirrorApplied: false)
        case (nil, let v?):
            return MirrorEvaluationResult(errorValue: v, mirrorApplied: true)
        case (let a?, let b?):
            if abs(b) < abs(a) {
                return MirrorEvaluationResult(errorValue: b, mirrorApplied: true)
            }
            return MirrorEvaluationResult(errorValue: a, mirrorApplied: false)
        }
    }

    private static func negate(_ output: MetricOutput?) -> MetricOutput? {
        guard let output else { return nil }
        guard let value = output.value else {
            return MetricOutput(value: nil, reason: output.reason)
        }
        return MetricOutput(value: -value, reason: output.reason)
    }

    private static func swap(
        _ metrics: inout [MetricKey: MetricOutput],
        _ a: MetricKey,
        _ b: MetricKey
    ) {
        let av = metrics[a]
        let bv = metrics[b]
        metrics[a] = bv
        metrics[b] = av
    }
}

enum WithRefErrorEvaluator {
    static func evaluate(
        metricKey: MetricKey,
        currentMetrics: [MetricKey: MetricOutput],
        mirroredMetrics: [MetricKey: MetricOutput]? = nil,
        target: Double?
    ) -> MirrorEvaluationResult? {
        guard let target else { return nil }

        let normalValue = currentMetrics[metricKey]?.value
        let normalError = normalValue.map { $0 - target }

        let mirrorMetrics = mirroredMetrics ?? MirrorEvaluator.mirrorMetricOutputs(currentMetrics)
        let mirrorValue = mirrorMetrics[metricKey]?.value
        let mirrorError = mirrorValue.map { $0 - target }

        return MirrorEvaluator.chooseSmallerError(normal: normalError, mirrored: mirrorError)
    }
}
