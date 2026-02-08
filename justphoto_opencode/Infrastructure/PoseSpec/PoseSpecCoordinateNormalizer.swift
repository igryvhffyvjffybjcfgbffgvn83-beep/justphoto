import CoreGraphics
import ImageIO

// M6.7: Normalize points into a single, portrait-normalized space.
//
// Contract: x/y are normalized to [0,1]. The output is always in `.up` portrait space.
enum PoseSpecCoordinateNormalizer {
    static func toPortraitNormalized(_ p: CGPoint, sourceOrientation: CGImagePropertyOrientation) -> CGPoint {
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
            // Mirror + rotate left.
            return CGPoint(x: 1 - y, y: 1 - x)
        case .rightMirrored:
            // Mirror + rotate right.
            return CGPoint(x: y, y: x)

        @unknown default:
            return CGPoint(x: x, y: y)
        }
    }
}
