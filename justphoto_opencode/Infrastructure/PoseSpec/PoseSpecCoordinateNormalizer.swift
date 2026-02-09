import CoreGraphics
import Foundation
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
    struct Shared: Sendable {
        func normalize(_ pVision: CGPoint, sourceOrientation: CGImagePropertyOrientation) -> CGPoint {
            PoseSpecCoordinateNormalizer.normalize(pVision, sourceOrientation: sourceOrientation)
        }

        func normalizeRect(_ rVision: CGRect, sourceOrientation: CGImagePropertyOrientation) -> CGRect {
            PoseSpecCoordinateNormalizer.normalizeRect(rVision, sourceOrientation: sourceOrientation)
        }
    }

    // M6.10: Instance-style API used by pipelines to prevent ad-hoc coordinate helpers.
    static let shared = Shared()

    /// Normalize a Vision-provided point into PoseSpec canonical space.
    static func normalize(_ pVision: CGPoint, sourceOrientation: CGImagePropertyOrientation) -> CGPoint {
        // Phase B1/B2: Vision is already given the correct EXIF orientation when we call
        // `VNSequenceRequestHandler.perform(... orientation: ...)`.
        // That means Vision results are already in the oriented (portrait) image space.
        // The only remaining conversion is Vision's Y-Up -> UIKit/metadata Y-Down.
        let out = CGPoint(x: pVision.x, y: 1.0 - pVision.y)

        #if DEBUG
        debugPrintNormalize(input: pVision, output: out, orientation: sourceOrientation)
        #endif

        return out
    }

    /// Normalize a Vision-provided rect into PoseSpec canonical space.
    static func normalizeRect(_ rVision: CGRect, sourceOrientation: CGImagePropertyOrientation) -> CGRect {
        // Same rationale as `normalize(_:...)`: do not rotate/transpose here.
        // For Y-Up rect (origin bottom-left), converting to Y-Down keeps size but moves origin.
        let x = rVision.origin.x
        let y = 1.0 - (rVision.origin.y + rVision.size.height)
        return CGRect(x: x, y: y, width: rVision.size.width, height: rVision.size.height)
    }

    #if DEBUG
    private static var _debugPrintCount: Int = 0
    private static var _debugLastPrintTsMs: Int = 0

    private static func debugPrintNormalize(input: CGPoint, output: CGPoint, orientation: CGImagePropertyOrientation) {
        // Prevent log spam: print the first few calls, then at most once per second.
        let nowMs = Int(Date().timeIntervalSince1970 * 1000)
        let shouldPrint = _debugPrintCount < 12 || nowMs - _debugLastPrintTsMs >= 1000
        guard shouldPrint else { return }

        _debugPrintCount += 1
        _debugLastPrintTsMs = nowMs
        print("PoseSpecNormalize: o=\(orientation.rawValue) in=\(input) out=\(output)")
    }
    #endif
}

// M6.8: Single Source of Truth alias used across the pipeline.
typealias CoordinateNormalizer = PoseSpecCoordinateNormalizer
