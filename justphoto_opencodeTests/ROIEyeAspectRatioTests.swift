import XCTest
import CoreGraphics

@testable import justphoto_opencode

final class ROIEyeAspectRatioTests: XCTestCase {
    func testEyeROIs_dropWhenAspectRatioIsBelowThreshold() {
        let leftEye = VisionLandmark(
            pPortrait: CGPoint(x: 0.35, y: 0.45),
            confidence: nil,
            aspectRatioHeightOverWidth: 0.10,
            precisionEstimatesPerPoint: [0.007]
        )
        let rightEye = VisionLandmark(
            pPortrait: CGPoint(x: 0.65, y: 0.45),
            confidence: nil,
            aspectRatioHeightOverWidth: 0.15,
            precisionEstimatesPerPoint: [0.007]
        )

        let face = VisionFaceResult(
            faceBBoxPortrait: CGRect(x: 0.25, y: 0.25, width: 0.50, height: 0.50),
            leftEyeCenter: leftEye,
            rightEyeCenter: rightEye,
            noseCenter: nil,
            faceConfidence: 1.0
        )

        let rois = ROIComputer.compute(face: face)
        XCTAssertNotNil(rois)
        XCTAssertEqual(rois?.eyeROIs.count, 0)
    }
}
