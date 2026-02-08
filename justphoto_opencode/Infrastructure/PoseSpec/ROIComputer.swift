import Foundation
import CoreGraphics

// M6.9: Compute ROI rectangles per PoseSpec rules.

struct ROISet: Sendable {
    let faceROI: CGRect
    let eyeROI: CGRect?
    let bgRingRects: [CGRect]
}

enum ROIComputer {
    static func compute(face: VisionFaceResult?) -> ROISet? {
        guard let face else { return nil }
        let rules = PoseSpecROIRulesCache.shared.rules

        let faceROI = computeFaceROI(faceBBox: face.faceBBoxPortrait, paddingX: rules.facePadX, paddingY: rules.facePadY)

        let eyeROI: CGRect?
        if let l = face.leftEyeCenter,
           let r = face.rightEyeCenter,
           l.confidence >= rules.minLandmarkConfidence,
           r.confidence >= rules.minLandmarkConfidence
        {
            eyeROI = computeEyeROI(leftEye: l.pPortrait, rightEye: r.pPortrait, wCoeff: rules.eyeWCoeff, hCoeff: rules.eyeHCoeff)
        } else {
            eyeROI = nil
        }

        let bg = computeBgRingRects(frame: CGRect(x: 0, y: 0, width: 1, height: 1), minus: faceROI)
        return ROISet(faceROI: faceROI, eyeROI: eyeROI, bgRingRects: bg)
    }

    private static func computeFaceROI(faceBBox: CGRect, paddingX: CGFloat, paddingY: CGFloat) -> CGRect {
        let dx = faceBBox.width * paddingX
        let dy = faceBBox.height * paddingY
        let expanded = faceBBox.insetBy(dx: -dx, dy: -dy)
        return clamp01(expanded)
    }

    private static func computeEyeROI(leftEye: CGPoint, rightEye: CGPoint, wCoeff: CGFloat, hCoeff: CGFloat) -> CGRect {
        let mid = CGPoint(x: (leftEye.x + rightEye.x) / 2.0, y: (leftEye.y + rightEye.y) / 2.0)
        let dx = leftEye.x - rightEye.x
        let dy = leftEye.y - rightEye.y
        let d = max(0, sqrt(dx * dx + dy * dy))

        let w = wCoeff * d
        let h = hCoeff * d
        let rect = CGRect(x: mid.x - w / 2.0, y: mid.y - h / 2.0, width: w, height: h)
        return clamp01(rect)
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

    private static func clamp01(_ r: CGRect) -> CGRect {
        clamp(CGRect(x: 0, y: 0, width: 1, height: 1), r)
    }

    private static func clamp(_ bounds: CGRect, _ r: CGRect) -> CGRect {
        let x0 = max(bounds.minX, r.minX)
        let y0 = max(bounds.minY, r.minY)
        let x1 = min(bounds.maxX, r.maxX)
        let y1 = min(bounds.maxY, r.maxY)
        if x1 <= x0 || y1 <= y0 {
            return .null
        }
        return CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
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

        guard let data = try? PoseSpecLoader.shared.loadData() else {
            return defaults
        }
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return defaults
        }

        var minConf = defaults.minLandmarkConfidence
        if let defaultsObj = root["defaults"] as? [String: Any],
           let confidenceObj = defaultsObj["confidence"] as? [String: Any],
           let n = confidenceObj["minLandmarkConfidence"] as? NSNumber
        {
            minConf = n.floatValue
        }

        var facePadX = defaults.facePadX
        var facePadY = defaults.facePadY
        var eyeW = defaults.eyeWCoeff
        var eyeH = defaults.eyeHCoeff

        if let rois = root["rois"] as? [String: Any] {
            if let face = rois["faceROI"] as? [String: Any],
               let pad = face["paddingPctOfBBox"] as? [String: Any]
            {
                if let x = pad["x"] as? NSNumber { facePadX = CGFloat(x.doubleValue) }
                if let y = pad["y"] as? NSNumber { facePadY = CGFloat(y.doubleValue) }
            }

            if let eye = rois["eyeROI"] as? [String: Any],
               let sizeRule = eye["sizeRule"] as? [String: Any]
            {
                if let w = sizeRule["w"] as? String, let c = parseCoeff(rule: w) { eyeW = c }
                if let h = sizeRule["h"] as? String, let c = parseCoeff(rule: h) { eyeH = c }
            }
        }

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
