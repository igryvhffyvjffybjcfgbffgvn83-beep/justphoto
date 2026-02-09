import CoreGraphics
import ImageIO

// M6.7: Canonical coordinate space for PoseSpec.
//
// Canonical Space (M6.7):
// - Normalized [0,1]
// - Portrait `.up` space
// - Y-Down (origin at top-left), consistent with UIKit/SwiftUI
//
// Vision commonly returns normalized points in Y-Up (origin at bottom-left).
// This normalizer performs the one-time flip (y = 1 - y) internally so all
// upper layers only ever see Y-Down.
enum PoseSpecCoordinateNormalizer {
    /// Normalize a Vision-provided point into PoseSpec canonical space.
    static func normalize(_ pVision: CGPoint, sourceOrientation: CGImagePropertyOrientation) -> CGPoint {
        // 1) Rotate/mirror into portrait `.up` space (still Y-Up).
        let pPortraitYUp = toPortraitNormalizedYUp(pVision, sourceOrientation: sourceOrientation)
        // 2) One-time flip into canonical Y-Down.
        return CGPoint(x: pPortraitYUp.x, y: 1.0 - pPortraitYUp.y)
    }

    /// Normalize a Vision-provided rect into PoseSpec canonical space.
    static func normalizeRect(_ rVision: CGRect, sourceOrientation: CGImagePropertyOrientation) -> CGRect {
        let corners = [
            CGPoint(x: rVision.minX, y: rVision.minY),
            CGPoint(x: rVision.maxX, y: rVision.minY),
            CGPoint(x: rVision.minX, y: rVision.maxY),
            CGPoint(x: rVision.maxX, y: rVision.maxY),
        ]

        let pts = corners.map { normalize($0, sourceOrientation: sourceOrientation) }
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

    // MARK: - Internal helpers
    // Portrait normalization in Y-Up (Vision native). Keep this private so the
    // rest of the app cannot accidentally re-introduce mixed coordinate spaces.
    private static func toPortraitNormalizedYUp(_ p: CGPoint, sourceOrientation: CGImagePropertyOrientation) -> CGPoint {
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

// M6.8: Single Source of Truth alias used across the pipeline.
typealias CoordinateNormalizer = PoseSpecCoordinateNormalizer
