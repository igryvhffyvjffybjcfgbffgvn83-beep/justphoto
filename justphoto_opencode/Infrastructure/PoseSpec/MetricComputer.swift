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

enum UnavailableReason: String, Sendable {
    case missingLandmark
    case lowConfidence
    case invalidBBox
}

struct MetricOutput: Sendable {
    let value: Double?
    let reason: UnavailableReason?

    static func available(_ value: Double) -> MetricOutput {
        MetricOutput(value: value, reason: nil)
    }

    static func unavailable(_ reason: UnavailableReason) -> MetricOutput {
        MetricOutput(value: nil, reason: reason)
    }
}

final class MetricComputer {
    static let shared = MetricComputer()

    private let poseNormalizer = PoseLandmarkNormalizer()
    private var cachedMinLandmarkConfidence: Float? = nil

    private init() {
        print("MetricContract loaded: T0_Count=\(MetricContractBook.t0Count) T1_Count=\(MetricContractBook.t1Count)")
    }

    func computeMetrics(context: MetricContext) -> [MetricKey: MetricOutput] {
        #if DEBUG
        dumpPoseLandmarksIfPossible(context: context)
        #endif

        var outputs: [MetricKey: MetricOutput] = [:]
        outputs.merge(computeBodyMetrics(context: context), uniquingKeysWith: { _, rhs in rhs })
        outputs.merge(computeFaceMetrics(context: context), uniquingKeysWith: { _, rhs in rhs })

        #if DEBUG
        printMetricOutputs(outputs)
        #endif

        return outputs
    }

    private func computeBodyMetrics(context: MetricContext) -> [MetricKey: MetricOutput] {
        let keys: [MetricKey] = [
            .centerXOffset,
            .centerYOffset,
            .bboxHeight,
            .headroom,
            .bottomMargin,
            .shoulderAngleDeg,
            .hipAngleDeg,
            .torsoLeanAngleDeg,
        ]

        func allUnavailable(_ reason: UnavailableReason) -> [MetricKey: MetricOutput] {
            var out: [MetricKey: MetricOutput] = [:]
            for key in keys {
                out[key] = .unavailable(reason)
            }
            return out
        }

        guard let specMinConf = loadMinLandmarkConfidence() else {
            return allUnavailable(.missingLandmark)
        }
        guard let obs = context.pose?.rawObservation?.observation else {
            return allUnavailable(.missingLandmark)
        }

        // Diagnostic override: relax min landmark confidence to improve availability.
        let minConf: Float = max(0.0, min(0.1, specMinConf))

        #if DEBUG
        debugLogBodyDiagnostics(context: context, observation: obs, minConf: minConf)
        #endif

        let rawPoints = poseNormalizer.normalize(observation: obs, minConfidence: minConf)
        guard !rawPoints.isEmpty else {
            return allUnavailable(.missingLandmark)
        }

        let points = OrientationFix.apply(rawPoints)
        #if DEBUG
        debugLogBodyBounds(rawPoints: rawPoints, fixedPoints: points)
        #endif
        let bbox = BodyBBoxBuilder.build(from: Array(points.values))
        guard bbox.isValid else {
            return allUnavailable(.missingLandmark)
        }

        var out: [MetricKey: MetricOutput] = [:]
        let center = bbox.center
        let rect = bbox.rect

        out[.centerXOffset] = .available(Double(center.x) - 0.5)
        out[.centerYOffset] = .available(Double(center.y) - 0.52)
        out[.bboxHeight] = .available(Double(rect.height))
        out[.headroom] = .available(Double(rect.minY))
        out[.bottomMargin] = .available(1.0 - Double(rect.maxY))

        let lShoulder = bodyPoint(.leftShoulder, in: points)
        let rShoulder = bodyPoint(.rightShoulder, in: points)
        if let lShoulder, let rShoulder {
            out[.shoulderAngleDeg] = .available(
                PoseGeometry.angleDeg(from: lShoulder.pPortrait, to: rShoulder.pPortrait)
            )
        } else {
            out[.shoulderAngleDeg] = .unavailable(.missingLandmark)
        }

        let lHip = bodyPoint(.leftHip, in: points)
        let rHip = bodyPoint(.rightHip, in: points)
        if let lHip, let rHip {
            out[.hipAngleDeg] = .available(
                PoseGeometry.angleDeg(from: lHip.pPortrait, to: rHip.pPortrait)
            )
        } else {
            out[.hipAngleDeg] = .unavailable(.missingLandmark)
        }

        if let lShoulder, let rShoulder, let lHip, let rHip {
            let shoulderMid = lShoulder.pPortrait.midpoint(to: rShoulder.pPortrait)
            let hipMid = lHip.pPortrait.midpoint(to: rHip.pPortrait)
            out[.torsoLeanAngleDeg] = .available(
                PoseGeometry.torsoLeanAngleDeg(hipMid: hipMid, shoulderMid: shoulderMid)
            )
        } else {
            out[.torsoLeanAngleDeg] = .unavailable(.missingLandmark)
        }

        return out
    }

    private func computeFaceMetrics(context: MetricContext) -> [MetricKey: MetricOutput] {
        let keys: [MetricKey] = [
            .eyeLineAngleDeg,
            .noseToChinRatio,
        ]

        func allUnavailable(_ reason: UnavailableReason) -> [MetricKey: MetricOutput] {
            var out: [MetricKey: MetricOutput] = [:]
            for key in keys {
                out[key] = .unavailable(reason)
            }
            return out
        }

        guard let face = context.face else {
            return allUnavailable(.missingLandmark)
        }

        let bbox = OrientationFix.apply(face.faceBBoxPortrait)
        guard bbox.width.isFinite, bbox.height.isFinite, bbox.width > 0, bbox.height > 0 else {
            return allUnavailable(.invalidBBox)
        }

        var out: [MetricKey: MetricOutput] = [:]

        if let lEye = face.leftEyeCenter?.pPortrait, let rEye = face.rightEyeCenter?.pPortrait {
            let lFixed = OrientationFix.apply(lEye)
            let rFixed = OrientationFix.apply(rEye)
            out[.eyeLineAngleDeg] = .available(PoseGeometry.angleDeg(from: lFixed, to: rFixed))
        } else {
            out[.eyeLineAngleDeg] = .unavailable(.missingLandmark)
        }

        if let nose = face.noseCenter?.pPortrait {
            let noseFixed = OrientationFix.apply(nose)
            let chinCenter = CGPoint(x: bbox.midX, y: bbox.maxY)
            let dist = PoseGeometry.distance(noseFixed, chinCenter)
            let ratio = dist / Double(bbox.height)
            out[.noseToChinRatio] = ratio.isFinite ? .available(ratio) : .unavailable(.invalidBBox)
        } else {
            out[.noseToChinRatio] = .unavailable(.missingLandmark)
        }

        return out
    }

    private func bodyPoint(
        _ joint: VNHumanBodyPoseObservation.JointName,
        in points: [String: BodyPoint]
    ) -> BodyPoint? {
        guard let key = LandmarkBindings.bodyJointToCanonicalKey[joint] else {
            return nil
        }
        return points[key]
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

    #if DEBUG
    private static let t0MetricKeys: [MetricKey] = [
        .centerXOffset,
        .centerYOffset,
        .bboxHeight,
        .headroom,
        .bottomMargin,
        .shoulderAngleDeg,
        .hipAngleDeg,
        .torsoLeanAngleDeg,
        .eyeLineAngleDeg,
        .noseToChinRatio,
    ]

    private func dumpPoseLandmarksIfPossible(context: MetricContext) {
        guard let minConf = loadMinLandmarkConfidence() else {
            return
        }

        guard let obs = context.pose?.rawObservation?.observation else {
            let thr = String(format: "%.2f", minConf)
            print("PoseSpecLandmarksDump: (no_pose)")
            print("BodyPointsStats: Total=0 Kept=0 Threshold=\(thr)")

            let r = BodyBBoxResult.invalid(reason: .insufficientPoints, pointCountUsed: 0)
            let reason = r.invalidReason?.rawValue ?? "unknown"
            print("BodyBBoxDump: Valid=false | Reason=\(reason) | Pts=0")
            return
        }

        let (rawPoints, stats) = poseNormalizer.normalizeWithStats(observation: obs, minConfidence: minConf)
        let points = OrientationFix.apply(rawPoints)

        // Dump a PoseSpec-like alias view for quick console verification.
        var parts: [String] = []
        for j in LandmarkBindings.orderedBodyJoints {
            guard let alias = LandmarkBindings.bodyJointToDebugAlias[j] else { continue }
            guard let key = LandmarkBindings.bodyJointToCanonicalKey[j] else { continue }
            guard let bp = points[key] else { continue }

            let x = Double(bp.pPortrait.x)
            let y = Double(bp.pPortrait.y)
            let c = Double(bp.confidence)
            let xStr = String(format: "%.3f", x)
            let yStr = String(format: "%.3f", y)
            let cStr = String(format: "%.2f", c)
            parts.append(
                "\(alias.rawValue)=(\(xStr), \(yStr)) conf=\(cStr)"
            )
        }

        if parts.isEmpty {
            print("PoseSpecLandmarksDump: (empty)")
        } else {
            print("PoseSpecLandmarksDump: \(parts.joined(separator: ", "))")
        }

        let thr = String(format: "%.2f", Double(stats.threshold))
        print("BodyPointsStats: Total=\(stats.totalCandidates) Kept=\(stats.kept) Threshold=\(thr) Dropped=\(stats.dropped)")

        let bbox = BodyBBoxBuilder.build(from: Array(points.values))
        if bbox.isValid {
            let rect = bbox.rect
            let rectStr = String(
                format: "[%.3f, %.3f, %.3f, %.3f]",
                rect.minX, rect.minY, rect.maxX, rect.maxY
            )
            let centerStr = String(format: "(%.3f, %.3f)", Double(bbox.center.x), Double(bbox.center.y))
            print("BodyBBoxDump: Valid=true | Pts=\(bbox.pointCountUsed) | Rect=\(rectStr) | Center=\(centerStr)")
        } else {
            let reason = bbox.invalidReason?.rawValue ?? "unknown"
            print(
                "BodyBBoxDump: Valid=false | Reason=\(reason) | Pts=\(bbox.pointCountUsed)"
            )
        }
    }

    private func printMetricOutputs(_ outputs: [MetricKey: MetricOutput]) {
        var parts: [String] = []
        for key in Self.t0MetricKeys {
            guard let output = outputs[key] else {
                parts.append("\(key.rawValue)=missing")
                continue
            }
            if let value = output.value, value.isFinite {
                let valueStr = String(format: "%.4f", value)
                parts.append("\(key.rawValue)=\(valueStr)")
            } else if let reason = output.reason {
                parts.append("\(key.rawValue)=unavailable(\(reason.rawValue))")
            } else {
                parts.append("\(key.rawValue)=unavailable(unknown)")
            }
        }
        print("PrintMetricOutputs: \(parts.joined(separator: " | "))")
    }

    private func debugLogBodyDiagnostics(
        context: MetricContext,
        observation: VNHumanBodyPoseObservation,
        minConf: Float
    ) {
        let allPoints = (try? observation.recognizedPoints(.all)) ?? [:]
        print("DEBUG_METRIC_ENTRY: Body Joints=\(allPoints.count) minConf=\(String(format: "%.2f", minConf))")

        let lShldr = try? observation.recognizedPoint(.leftShoulder)
        let rShldr = try? observation.recognizedPoint(.rightShoulder)
        let lConf = lShldr?.confidence ?? -1
        let rConf = rShldr?.confidence ?? -1
        print("DEBUG_CONFIDENCE: L.Shldr=\(String(format: "%.2f", lConf)) R.Shldr=\(String(format: "%.2f", rConf))")

        let orientation = context.orientation ?? .up
        if let l = lShldr, let r = rShldr {
            let lNorm = PoseSpecCoordinateNormalizer.normalize(l.location, sourceOrientation: orientation)
            let rNorm = PoseSpecCoordinateNormalizer.normalize(r.location, sourceOrientation: orientation)
            let lFixed = OrientationFix.apply(lNorm)
            let rFixed = OrientationFix.apply(rNorm)
            print("DEBUG_FIXED_COORDS: L=\(lFixed) R=\(rFixed)")
            if lFixed.x > 1.0 || lFixed.y > 1.0 || lFixed.x < 0.0 || lFixed.y < 0.0 {
                print("⚠️ WARN: L shoulder out of bounds!")
            }
            if rFixed.x > 1.0 || rFixed.y > 1.0 || rFixed.x < 0.0 || rFixed.y < 0.0 {
                print("⚠️ WARN: R shoulder out of bounds!")
            }
        } else {
            print("DEBUG_METRIC_ENTRY: missing left/right shoulder points")
        }
    }

    private func debugLogBodyBounds(rawPoints: [String: BodyPoint], fixedPoints: [String: BodyPoint]) {
        func bounds(for points: [String: BodyPoint]) -> (minX: Double, minY: Double, maxX: Double, maxY: Double)? {
            guard !points.isEmpty else { return nil }
            var minX = Double.greatestFiniteMagnitude
            var minY = Double.greatestFiniteMagnitude
            var maxX = -Double.greatestFiniteMagnitude
            var maxY = -Double.greatestFiniteMagnitude
            for p in points.values {
                let x = Double(p.pPortrait.x)
                let y = Double(p.pPortrait.y)
                minX = min(minX, x)
                minY = min(minY, y)
                maxX = max(maxX, x)
                maxY = max(maxY, y)
            }
            return (minX, minY, maxX, maxY)
        }

        if let b = bounds(for: rawPoints) {
            print("DEBUG_RAW_BOUNDS: min=(\(String(format: "%.3f", b.minX)), \(String(format: "%.3f", b.minY))) max=(\(String(format: "%.3f", b.maxX)), \(String(format: "%.3f", b.maxY)))")
        } else {
            print("DEBUG_RAW_BOUNDS: empty")
        }

        if let b = bounds(for: fixedPoints) {
            print("DEBUG_FIXED_BOUNDS: min=(\(String(format: "%.3f", b.minX)), \(String(format: "%.3f", b.minY))) max=(\(String(format: "%.3f", b.maxX)), \(String(format: "%.3f", b.maxY)))")
        } else {
            print("DEBUG_FIXED_BOUNDS: empty")
        }
    }
    #endif
}

private enum OrientationFix {
    static func apply(_ p: CGPoint) -> CGPoint {
        CGPoint(x: p.y, y: p.x)
    }

    static func apply(_ r: CGRect) -> CGRect {
        CGRect(x: r.minY, y: r.minX, width: r.height, height: r.width)
    }

    static func apply(_ points: [String: BodyPoint]) -> [String: BodyPoint] {
        var out: [String: BodyPoint] = [:]
        out.reserveCapacity(points.count)
        for (k, v) in points {
            out[k] = BodyPoint(pPortrait: apply(v.pPortrait), confidence: v.confidence)
        }
        return out
    }
}

private enum PoseGeometry {
    static func distance(_ a: CGPoint, _ b: CGPoint) -> Double {
        let dx = Double(b.x - a.x)
        let dy = Double(b.y - a.y)
        return (dx * dx + dy * dy).squareRoot()
    }

    static func angleDeg(from a: CGPoint, to b: CGPoint) -> Double {
        let dx = Double(b.x - a.x)
        let dy = Double(b.y - a.y)
        return atan2(dy, dx) * 180.0 / Double.pi
    }

    static func torsoLeanAngleDeg(hipMid: CGPoint, shoulderMid: CGPoint) -> Double {
        let dx = Double(hipMid.x - shoulderMid.x)
        let dy = Double(hipMid.y - shoulderMid.y)
        return atan2(dx, -dy) * 180.0 / Double.pi
    }
}

private extension CGPoint {
    func midpoint(to other: CGPoint) -> CGPoint {
        CGPoint(x: (x + other.x) * 0.5, y: (y + other.y) * 0.5)
    }

    func distance(to other: CGPoint) -> Double {
        PoseGeometry.distance(self, other)
    }

    func angleDeg(to other: CGPoint) -> Double {
        PoseGeometry.angleDeg(from: self, to: other)
    }
}
