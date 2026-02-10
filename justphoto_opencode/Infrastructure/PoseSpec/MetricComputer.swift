import Foundation
import CoreVideo
import ImageIO

// M6.10 Phase 1: MetricComputer scaffold.
// This milestone intentionally does NOT implement any math.

struct MetricContext {
    let pose: VisionPoseResult?
    let face: VisionFaceResult?
    let rois: ROISet?
    let pixelBuffer: CVPixelBuffer?
    let orientation: CGImagePropertyOrientation?
}

final class MetricComputer {
    static let shared = MetricComputer()

    private init() {
        print("MetricContract loaded: T0_Count=\(MetricContractBook.t0Count) T1_Count=\(MetricContractBook.t1Count)")
    }

    func computeMetrics(context: MetricContext) -> [MetricKey: Double] {
        _ = context
        return [:]
    }
}
