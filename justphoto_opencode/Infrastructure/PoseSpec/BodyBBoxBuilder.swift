import CoreGraphics
import Foundation

// M6.10 Phase 2: Build a debug-friendly body bounding box from already-filtered BodyPoints.

struct BodyBBoxResult: Sendable {
    enum InvalidReason: String, Sendable {
        case insufficientPoints
        case lowConfidence
        case degenerateBBox
    }

    let isValid: Bool
    let invalidReason: InvalidReason?

    // Portrait-normalized unit space, clamped to [0,1].
    // Invalid results use `.null` to avoid ghost data.
    let rect: CGRect
    let center: CGPoint

    let pointCountUsed: Int

    static func invalid(reason: InvalidReason, pointCountUsed: Int) -> BodyBBoxResult {
        BodyBBoxResult(
            isValid: false,
            invalidReason: reason,
            rect: .null,
            center: .zero,
            pointCountUsed: pointCountUsed
        )
    }
}

enum BodyBBoxBuilder {
    private static let unit = CGRect(x: 0, y: 0, width: 1, height: 1)

    static func build(from points: [BodyPoint]) -> BodyBBoxResult {
        guard points.count >= 3 else {
            return .invalid(reason: .insufficientPoints, pointCountUsed: points.count)
        }

        let xs = points.map { $0.pPortrait.x }
        let ys = points.map { $0.pPortrait.y }

        guard let minX = xs.min(),
              let maxX = xs.max(),
              let minY = ys.min(),
              let maxY = ys.max()
        else {
            return .invalid(reason: .insufficientPoints, pointCountUsed: points.count)
        }

        let width = maxX - minX
        let height = maxY - minY
        guard width > 0, height > 0 else {
            return .invalid(reason: .degenerateBBox, pointCountUsed: points.count)
        }

        let raw = CGRect(x: minX, y: minY, width: width, height: height).standardized

        let clamped = raw.intersection(unit)
        guard !clamped.isNull, !clamped.isEmpty, clamped.width > 0, clamped.height > 0 else {
            return .invalid(reason: .degenerateBBox, pointCountUsed: points.count)
        }

        let center = CGPoint(x: clamped.midX, y: clamped.midY)
        return BodyBBoxResult(
            isValid: true,
            invalidReason: nil,
            rect: clamped,
            center: center,
            pointCountUsed: points.count
        )
    }
}
