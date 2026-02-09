import Foundation
import CoreGraphics

// M6.9: Compute ROI rectangles per PoseSpec rules.

struct ROISet: Sendable {
    let faceROI: CGRect
    let eyeROIs: [CGRect]
    let bgRingRects: [CGRect]
}

enum ROIComputer {
    static func compute(face: VisionFaceResult?) -> ROISet? {
        guard let face else { return nil }
        let rules = PoseSpecROIRulesCache.shared.rules

        let unit = CGRect(x: 0, y: 0, width: 1, height: 1)

        // Phase B1: Last-line-of-defense clamp before returning any ROI (prevents out-of-bounds crop crashes).
        let faceROI = clampToUnit(computeFaceROI(faceBBox: face.faceBBoxPortrait, paddingX: rules.facePadX, paddingY: rules.facePadY), unit: unit)
        if faceROI.isNull || faceROI.isEmpty {
            return nil
        }

        // Phase B1: Fix "one-eye" geometry/iteration bug by explicitly computing left/right eye ROIs.
        // We intentionally do not do confidence filtering in this phase.
        let d: CGFloat = {
            if let l = face.leftEyeCenter?.pPortrait, let r = face.rightEyeCenter?.pPortrait {
                let dx = l.x - r.x
                let dy = l.y - r.y
                return max(0, sqrt(dx * dx + dy * dy))
            }
            // Fallback scale if only one eye is available.
            return max(0.0001, max(face.faceBBoxPortrait.width, face.faceBBoxPortrait.height) * 0.25)
        }()

        var eyeROIs: [CGRect] = []
        let perEyeW = rules.eyeWCoeff * 0.5
        let perEyeH = rules.eyeHCoeff * 0.5

        if let leftEye = face.leftEyeCenter {
            let raw = computeEyeROI(eyeCenter: leftEye.pPortrait, scale: d, wCoeff: perEyeW, hCoeff: perEyeH)
            let clamped = clampToUnit(raw, unit: unit)
            if !clamped.isNull && !clamped.isEmpty {
                eyeROIs.append(clamped)
            }
        }
        if let rightEye = face.rightEyeCenter {
            let raw = computeEyeROI(eyeCenter: rightEye.pPortrait, scale: d, wCoeff: perEyeW, hCoeff: perEyeH)
            let clamped = clampToUnit(raw, unit: unit)
            if !clamped.isNull && !clamped.isEmpty {
                eyeROIs.append(clamped)
            }
        }

        let bg = computeBgRingRects(frame: unit, minus: faceROI)
            .map { clampToUnit($0, unit: unit) }
            .filter { !$0.isNull && !$0.isEmpty && $0.width > 0.0001 && $0.height > 0.0001 }

        return ROISet(faceROI: faceROI, eyeROIs: eyeROIs, bgRingRects: bg)
    }

    private static func computeFaceROI(faceBBox: CGRect, paddingX: CGFloat, paddingY: CGFloat) -> CGRect {
        let dx = faceBBox.width * paddingX
        let dy = faceBBox.height * paddingY
        let expanded = faceBBox.insetBy(dx: -dx, dy: -dy)
        return expanded
    }

    private static func computeEyeROI(eyeCenter: CGPoint, scale: CGFloat, wCoeff: CGFloat, hCoeff: CGFloat) -> CGRect {
        let w = max(0, wCoeff * scale)
        let h = max(0, hCoeff * scale)
        return CGRect(x: eyeCenter.x - w / 2.0, y: eyeCenter.y - h / 2.0, width: w, height: h)
    }

    private static func computeBgRingRects(frame: CGRect, minus roi: CGRect) -> [CGRect] {
        let m = clamp(frame, roi)
        if m.isNull || m.isEmpty {
            return [frame]
        }

        let top = CGRect(x: frame.minX, y: m.maxY, width: frame.width, height: frame.maxY - m.maxY)
        let bottom = CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: m.minY - frame.minY)
        let left = CGRect(x: frame.minX, y: m.minY, width: m.minX - frame.minX, height: m.height)
        let right = CGRect(x: m.maxX, y: m.minY, width: frame.maxX - m.maxX, height: m.height)

        return [top, bottom, left, right]
            .map { clamp(frame, $0) }
            .filter { !$0.isNull && !$0.isEmpty && $0.width > 0.0001 && $0.height > 0.0001 }
    }

    private static func clampToUnit(_ r: CGRect, unit: CGRect) -> CGRect {
        guard let s = sanitize(r) else { return .null }
        let inter = s.intersection(unit)
        if inter.isNull || inter.isEmpty {
            return .null
        }
        return inter
    }

    private static func clamp(_ bounds: CGRect, _ r: CGRect) -> CGRect {
        guard let rr = sanitize(r) else { return .null }
        let inter = bounds.standardized.intersection(rr)
        if inter.isNull || inter.isEmpty {
            return .null
        }
        return inter
    }

    private static func sanitize(_ r: CGRect) -> CGRect? {
        let s = r.standardized
        guard s.origin.x.isFinite,
              s.origin.y.isFinite,
              s.size.width.isFinite,
              s.size.height.isFinite
        else {
            return nil
        }
        return s
    }
}

private struct PoseSpecROIRules: Sendable {
    let minLandmarkConfidence: Float
    let facePadX: CGFloat
    let facePadY: CGFloat
    let eyeWCoeff: CGFloat
    let eyeHCoeff: CGFloat

    static func loadOrDefault() -> PoseSpecROIRules {
        let defaults = PoseSpecROIRules(
            minLandmarkConfidence: 0.5,
            facePadX: 0.15,
            facePadY: 0.15,
            eyeWCoeff: 2.2,
            eyeHCoeff: 1.2
        )

        guard let spec = try? PoseSpecLoader.shared.loadPoseSpec() else {
            return defaults
        }

        var minConf = Float(spec.defaults.confidence.minLandmarkConfidence)
        var facePadX = defaults.facePadX
        var facePadY = defaults.facePadY
        if let faceROI = spec.rois.faceROI {
            facePadX = CGFloat(faceROI.paddingPctOfBBox.x)
            facePadY = CGFloat(faceROI.paddingPctOfBBox.y)
        }

        var eyeW = defaults.eyeWCoeff
        var eyeH = defaults.eyeHCoeff
        if let eyeROI = spec.rois.eyeROI {
            if let c = parseCoeff(rule: eyeROI.sizeRule.w) { eyeW = c }
            if let c = parseCoeff(rule: eyeROI.sizeRule.h) { eyeH = c }
        }

        // If the JSON changes or decoding succeeds with unexpected zeros, keep safe defaults.
        if minConf <= 0 { minConf = defaults.minLandmarkConfidence }
        if facePadX < 0 { facePadX = defaults.facePadX }
        if facePadY < 0 { facePadY = defaults.facePadY }

        return PoseSpecROIRules(
            minLandmarkConfidence: minConf,
            facePadX: facePadX,
            facePadY: facePadY,
            eyeWCoeff: eyeW,
            eyeHCoeff: eyeH
        )
    }

    private static func parseCoeff(rule: String) -> CGFloat? {
        // Examples: "2.2 * interOcularDistance"
        let trimmed = rule.replacingOccurrences(of: " ", with: "")
        guard let starIdx = trimmed.firstIndex(of: "*") else { return nil }
        let lhs = trimmed[..<starIdx]
        guard let d = Double(lhs) else { return nil }
        return CGFloat(d)
    }
}

private final class PoseSpecROIRulesCache: @unchecked Sendable {
    static let shared = PoseSpecROIRulesCache()
    let rules: PoseSpecROIRules
    private init() {
        self.rules = PoseSpecROIRules.loadOrDefault()
    }
}
