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
    private enum MetricMissingDetailReason: String {
        case lowConf = "low_conf"
        case outOfRange = "out_of_range"
        case missingInput = "missing_input"
        case bboxInvalid = "bbox_invalid"
    }

    private struct BodyMetricComputeResult {
        let outputs: [MetricKey: MetricOutput]
        let unavailableDetails: [MetricKey: String]
    }

    static let shared = MetricComputer(debugLogEnabled: true)

    static func makeIsolated() -> MetricComputer {
        MetricComputer(debugLogEnabled: false)
    }

    private let debugLogEnabled: Bool
    private let frameMetricComputer = FrameMetricComputer()
    private var cachedMinLandmarkConfidence: Float? = nil
#if DEBUG
    private var cachedAntiJitterDefaults: AntiJitterDefaults? = nil
    private lazy var antiJitterGate: AntiJitterGate = {
        let defaults = loadAntiJitterDefaults()
        return AntiJitterGate(
            persistFrames: defaults?.persistFrames ?? 6,
            minHoldMs: defaults?.minHoldMs ?? 3000,
            cooldownMs: defaults?.cooldownMs ?? 800
        )
    }()
    private var lastJitterLog: String? = nil
#endif

    private init(debugLogEnabled: Bool) {
        self.debugLogEnabled = debugLogEnabled
        if debugLogEnabled {
            print("MetricContract loaded: T0_Count=\(MetricContractBook.t0Count) T1_Count=\(MetricContractBook.t1Count)")
        }
    }

    func computeMetrics(context: MetricContext) -> [MetricKey: MetricOutput] {
        #if DEBUG
        dumpPoseLandmarksIfPossible(context: context)
        #endif

        var outputs: [MetricKey: MetricOutput] = [:]
        let bodyResult = computeBodyMetrics(context: context)
        outputs.merge(bodyResult.outputs, uniquingKeysWith: { _, rhs in rhs })
        outputs.merge(computeFaceMetrics(context: context), uniquingKeysWith: { _, rhs in rhs })
        outputs.merge(computeFrameMetrics(context: context), uniquingKeysWith: { _, rhs in rhs })

        #if DEBUG
        printMetricOutputs(outputs, unavailableDetails: bodyResult.unavailableDetails)
        debugRunAntiJitterProbe(outputs: outputs)
        #endif

        return outputs
    }

    private func computeBodyMetrics(context: MetricContext) -> BodyMetricComputeResult {
        let bboxKeys: [MetricKey] = [
            .centerXOffset,
            .centerYOffset,
            .bboxHeight,
            .headroom,
            .bottomMargin,
        ]
        let jointKeys: [MetricKey] = [
            .shoulderAngleDeg,
            .hipAngleDeg,
            .torsoLeanAngleDeg,
        ]
        let allKeys = bboxKeys + jointKeys

        var out: [MetricKey: MetricOutput] = [:]
        var unavailableDetails: [MetricKey: String] = [:]

        func markUnavailable(_ key: MetricKey, detail: String) {
            out[key] = .unavailable(.missingLandmark)
            unavailableDetails[key] = detail
        }

        func markAllUnavailable(detail: String) {
            for key in allKeys {
                markUnavailable(key, detail: detail)
            }
        }

        guard let specMinConf = loadMinLandmarkConfidence() else {
            markAllUnavailable(detail: "\(MetricMissingDetailReason.missingInput.rawValue):confidence_rule_unavailable")
            return BodyMetricComputeResult(outputs: out, unavailableDetails: unavailableDetails)
        }
        guard let pose = context.pose else {
            markAllUnavailable(detail: "\(MetricMissingDetailReason.missingInput.rawValue):no_pose")
            return BodyMetricComputeResult(outputs: out, unavailableDetails: unavailableDetails)
        }
        let points = canonicalBodyPoints(from: pose)

        #if DEBUG
        debugLogBodyDiagnostics(context: context, pose: pose, minConf: max(0.0, min(1.0, specMinConf)))
        debugLogBodyBounds(points: points)
        #endif

        guard !points.isEmpty else {
            let fallbackReason = dominantDropReason(in: pose)?.rawValue ?? PosePointDropReason.missingInput.rawValue
            markAllUnavailable(detail: fallbackReason)
            return BodyMetricComputeResult(outputs: out, unavailableDetails: unavailableDetails)
        }

        // Joint metrics: never depend on bbox validity.
        let lShoulder = bodyPoint(.leftShoulder, in: points)
        let rShoulder = bodyPoint(.rightShoulder, in: points)
        if let lShoulder, let rShoulder {
            out[.shoulderAngleDeg] = .available(
                PoseGeometry.angleDeg(from: lShoulder.pPortrait, to: rShoulder.pPortrait)
            )
        } else {
            markUnavailable(
                .shoulderAngleDeg,
                detail: "\(MetricMissingDetailReason.missingInput.rawValue):lShoulder=\(missingJointReason(.leftShoulder, pose: pose))|rShoulder=\(missingJointReason(.rightShoulder, pose: pose))"
            )
        }

        let lHip = bodyPoint(.leftHip, in: points)
        let rHip = bodyPoint(.rightHip, in: points)
        if let lHip, let rHip {
            out[.hipAngleDeg] = .available(
                PoseGeometry.angleDeg(from: lHip.pPortrait, to: rHip.pPortrait)
            )
        } else {
            markUnavailable(
                .hipAngleDeg,
                detail: "\(MetricMissingDetailReason.missingInput.rawValue):lHip=\(missingJointReason(.leftHip, pose: pose))|rHip=\(missingJointReason(.rightHip, pose: pose))"
            )
        }

        if let lShoulder, let rShoulder, let lHip, let rHip {
            let shoulderMid = lShoulder.pPortrait.midpoint(to: rShoulder.pPortrait)
            let hipMid = lHip.pPortrait.midpoint(to: rHip.pPortrait)
            out[.torsoLeanAngleDeg] = .available(
                PoseGeometry.torsoLeanAngleDeg(hipMid: hipMid, shoulderMid: shoulderMid)
            )
        } else {
            markUnavailable(
                .torsoLeanAngleDeg,
                detail: "\(MetricMissingDetailReason.missingInput.rawValue):shoulders_or_hips_unavailable"
            )
        }

        // BBox metrics: only these depend on bbox validity.
        let bbox = BodyBBoxBuilder.build(from: Array(points.values))
        if bbox.isValid {
            let center = bbox.center
            let rect = bbox.rect
            out[.centerXOffset] = .available(Double(center.x) - 0.5)
            out[.centerYOffset] = .available(Double(center.y) - 0.52)
            out[.bboxHeight] = .available(Double(rect.height))
            out[.headroom] = .available(Double(rect.minY))
            out[.bottomMargin] = .available(1.0 - Double(rect.maxY))
        } else {
            let bboxReason = bbox.invalidReason?.rawValue ?? "bbox_invalid"
            for key in bboxKeys {
                markUnavailable(key, detail: "\(MetricMissingDetailReason.bboxInvalid.rawValue):\(bboxReason)")
            }
        }

        return BodyMetricComputeResult(outputs: out, unavailableDetails: unavailableDetails)
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

        let bbox = face.faceBBoxPortrait
        guard bbox.width.isFinite, bbox.height.isFinite, bbox.width > 0, bbox.height > 0 else {
            return allUnavailable(.invalidBBox)
        }

        var out: [MetricKey: MetricOutput] = [:]

        if let lEye = face.leftEyeCenter?.pPortrait, let rEye = face.rightEyeCenter?.pPortrait {
            out[.eyeLineAngleDeg] = .available(PoseGeometry.angleDeg(from: lEye, to: rEye))
        } else {
            out[.eyeLineAngleDeg] = .unavailable(.missingLandmark)
        }

        if let nose = face.noseCenter?.pPortrait {
            let chinCenter = CGPoint(x: bbox.midX, y: bbox.maxY)
            let dist = PoseGeometry.distance(nose, chinCenter)
            let ratio = dist / Double(bbox.height)
            out[.noseToChinRatio] = ratio.isFinite ? .available(ratio) : .unavailable(.invalidBBox)
        } else {
            out[.noseToChinRatio] = .unavailable(.missingLandmark)
        }

        return out
    }

    private func computeFrameMetrics(context: MetricContext) -> [MetricKey: MetricOutput] {
        var out: [MetricKey: MetricOutput] = [:]

        #if DEBUG
        print("DEBUG_T1: Checking T1 conditions...")
        #endif

        guard let pixelBuffer = context.pixelBuffer else {
            #if DEBUG
            print("DEBUG_T1: Buffer is nil!")
            #endif
            out[.faceLumaMean] = .unavailable(.missingLandmark)
            return out
        }
        guard let rois = context.rois ?? ROIComputer.compute(pose: context.pose, face: context.face) else {
            #if DEBUG
            print("DEBUG_T1: ROI set is nil!")
            #endif
            out[.faceLumaMean] = .unavailable(.missingLandmark)
            return out
        }

        let faceROI = rois.roiDict["faceROI"] ?? .null
        guard !faceROI.isNull, !faceROI.isEmpty else {
            #if DEBUG
            print("DEBUG_T1: faceROI invalid")
            #endif
            out[.faceLumaMean] = .unavailable(.invalidBBox)
            return out
        }

        guard let rawMean = frameMetricComputer.computeFaceLumaMean(pixelBuffer: pixelBuffer, faceROI: faceROI) else {
            return out
        }

        out[.faceLumaMean] = .available(rawMean)

        #if DEBUG
        let rawStr = String(format: "%.3f", rawMean)
        print("T1FaceLuma: raw=\(rawStr) error=na")
        #endif

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

    private func canonicalBodyPoints(from pose: VisionPoseResult) -> [String: BodyPoint] {
        var out: [String: BodyPoint] = [:]
        out.reserveCapacity(pose.points.count)
        for (key, landmark) in pose.points {
            guard let conf = landmark.confidence, conf.isFinite else { continue }
            let p = landmark.pPortrait
            guard p.x.isFinite, p.y.isFinite,
                  p.x >= 0.0, p.x <= 1.0,
                  p.y >= 0.0, p.y <= 1.0 else {
                continue
            }
            out[key] = BodyPoint(pPortrait: p, confidence: conf)
        }
        return out
    }

    private func missingJointReason(
        _ joint: VNHumanBodyPoseObservation.JointName,
        pose: VisionPoseResult
    ) -> String {
        guard let key = LandmarkBindings.bodyJointToCanonicalKey[joint] else {
            return MetricMissingDetailReason.missingInput.rawValue
        }
        if pose.points[key] != nil {
            return "available"
        }
        return pose.droppedReasonsByJointKey[key]?.rawValue ?? MetricMissingDetailReason.missingInput.rawValue
    }

    private func dominantDropReason(in pose: VisionPoseResult) -> PosePointDropReason? {
        var counts: [PosePointDropReason: Int] = [:]
        for reason in pose.droppedReasonsByJointKey.values {
            counts[reason, default: 0] += 1
        }
        return counts.max { $0.value < $1.value }?.key
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
    private func loadAntiJitterDefaults() -> AntiJitterDefaults? {
        if let v = cachedAntiJitterDefaults {
            return v
        }
        guard let spec = try? PoseSpecLoader.shared.loadPoseSpec() else {
            return nil
        }
        let v = spec.defaults.antiJitter
        cachedAntiJitterDefaults = v
        return v
    }

    private func debugRunAntiJitterProbe(outputs: [MetricKey: MetricOutput]) {
        let tsMs = Int(Date().timeIntervalSince1970 * 1000)
        let centerX = outputs[.centerXOffset]?.value
        let hardThreshold: Double = 0.12

        let selection: CueSelectionResult? = {
            guard let v = centerX, v.isFinite else { return nil }
            let cueId: String
            if v > hardThreshold {
                cueId = "FRAME_MOVE_LEFT"
            } else if v < -hardThreshold {
                cueId = "FRAME_MOVE_RIGHT"
            } else {
                return nil
            }

            let eval = CueEvaluationResult(
                cueId: cueId,
                level: .hard,
                matchedThresholdId: "hard:>0.12",
                evaluatedThresholdCount: 1,
                usedRefMode: .noRef
            )
            let candidate = CueSelectionCandidate(
                cueId: cueId,
                priority: 4,
                mutexGroup: "FRAME_X",
                evaluation: eval,
                errorValue: v,
                hardThresholdAbs: hardThreshold
            )
            return CueSelector.pickOne([candidate])
        }()

        let input: AntiJitterInput? = selection.map {
            AntiJitterInput(cueId: $0.candidate.cueId, level: $0.candidate.evaluation.level)
        }

        let (output, rawReason) = antiJitterGate.filterWithReason(inputCue: input, timestampMs: tsMs)
        let candFrames = antiJitterGate.stableFrameCount
        let holdMs = max(0, tsMs - antiJitterGate.lastOutputChangeMs)
        let cooldownUntil: Int
        if let input, let until = antiJitterGate.cooldownUntilByCueId[input.cueId] {
            cooldownUntil = until
        } else {
            cooldownUntil = 0
        }
        let cooldownLeft = max(0, cooldownUntil - tsMs)

        let outputStr: String = {
            guard let output else { return "nil" }
            return "\(output.cueId)/\(output.level.rawValue)"
        }()

        let reason = (rawReason == "frames") ? "hold" : rawReason
        let line: String
        if let input {
            let inputStr = "\(input.cueId)/\(input.level.rawValue)"
            line = "Jitter: input=\(inputStr) candFrames=\(candFrames) holdMs=\(holdMs) cooldownLeft=\(cooldownLeft) -> output=\(outputStr) reason=\(reason)"
        } else {
            line = "Jitter: input=nil -> output=\(outputStr) reason=\(reason)"
        }

        if line != lastJitterLog {
            print(line)
            lastJitterLog = line
        }
    }
    #endif

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

        guard let pose = context.pose else {
            let thr = String(format: "%.2f", minConf)
            print("PoseSpecLandmarksDump: (no_pose)")
            print("BodyPointsStats: Total=0 Kept=0 Threshold=\(thr)")

            let r = BodyBBoxResult.invalid(reason: .insufficientPoints, pointCountUsed: 0)
            let reason = r.invalidReason?.rawValue ?? "unknown"
            print("BodyBBoxDump: Valid=false | Reason=\(reason) | Pts=0")
            return
        }

        let points = canonicalBodyPoints(from: pose)
        let stats = pose.canonicalizationStats ?? PoseCanonicalizationStats(
            totalCandidates: points.count,
            kept: points.count,
            threshold: minConf
        )

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
        if !pose.droppedReasonsByJointKey.isEmpty {
            let dropped = pose.droppedReasonsByJointKey
                .sorted { $0.key < $1.key }
                .map { "\($0.key):\($0.value.rawValue)" }
                .joined(separator: ",")
            print("BodyPointDroppedReasons: \(dropped)")
        }

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

    private func printMetricOutputs(
        _ outputs: [MetricKey: MetricOutput],
        unavailableDetails: [MetricKey: String]
    ) {
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
                if let detail = unavailableDetails[key], !detail.isEmpty {
                    parts.append("\(key.rawValue)=unavailable(\(reason.rawValue):\(detail))")
                } else {
                    parts.append("\(key.rawValue)=unavailable(\(reason.rawValue))")
                }
            } else {
                parts.append("\(key.rawValue)=unavailable(unknown)")
            }
        }
        print("PrintMetricOutputs: \(parts.joined(separator: " | "))")
    }

    private func debugLogBodyDiagnostics(
        context: MetricContext,
        pose: VisionPoseResult,
        minConf: Float
    ) {
        let stats = pose.canonicalizationStats
        let total = stats?.totalCandidates ?? pose.points.count
        let kept = stats?.kept ?? pose.points.count
        print("DEBUG_METRIC_ENTRY: Body Joints=\(total) kept=\(kept) minConf=\(String(format: "%.2f", minConf))")

        let lShldr = bodyPoint(.leftShoulder, in: canonicalBodyPoints(from: pose))
        let rShldr = bodyPoint(.rightShoulder, in: canonicalBodyPoints(from: pose))
        let lConf = lShldr?.confidence ?? -1
        let rConf = rShldr?.confidence ?? -1
        print("DEBUG_CONFIDENCE: L.Shldr=\(String(format: "%.2f", lConf)) R.Shldr=\(String(format: "%.2f", rConf))")

        _ = context
        let lFixed = debugFixedPointString(point: lShldr)
        let rFixed = debugFixedPointString(point: rShldr)
        print("DEBUG_FIXED_COORDS: L=\(lFixed) R=\(rFixed)")
    }

    private func debugFixedPointString(
        point: BodyPoint?
    ) -> String {
        guard let point else {
            return "missing(no_point)"
        }
        let p = point.pPortrait
        guard p.x.isFinite, p.y.isFinite,
              p.x >= 0.0, p.x <= 1.0,
              p.y >= 0.0, p.y <= 1.0 else {
            return "missing(out_of_range)"
        }
        return String(format: "(%.3f, %.3f)", p.x, p.y)
    }

    private func debugLogBodyBounds(points: [String: BodyPoint]) {
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

        if let b = bounds(for: points) {
            print("DEBUG_FIXED_BOUNDS: min=(\(String(format: "%.3f", b.minX)), \(String(format: "%.3f", b.minY))) max=(\(String(format: "%.3f", b.maxX)), \(String(format: "%.3f", b.maxY)))")
        } else {
            print("DEBUG_FIXED_BOUNDS: empty")
        }
    }
    #endif
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
