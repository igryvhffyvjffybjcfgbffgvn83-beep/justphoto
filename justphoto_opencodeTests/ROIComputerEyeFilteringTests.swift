import XCTest
import CoreGraphics

@testable import justphoto_opencode

final class ROIComputerEyeFilteringTests: XCTestCase {
    func testEyeROIs_areComputedIndependently_whenOneEyeFailsPrecisionGate() {
        // Phase B2: precision estimates are "smaller is better".
        // Left eye has a bad worst-point precision => should be dropped; right should remain.
        let leftEye = VisionLandmark(pPortrait: CGPoint(x: 0.35, y: 0.45), confidence: nil, aspectRatioHeightOverWidth: 0.40, precisionEstimatesPerPoint: [0.020])
        let rightEye = VisionLandmark(pPortrait: CGPoint(x: 0.65, y: 0.45), confidence: nil, aspectRatioHeightOverWidth: 0.40, precisionEstimatesPerPoint: [0.007])

        let face = VisionFaceResult(
            faceBBoxPortrait: CGRect(x: 0.25, y: 0.25, width: 0.50, height: 0.50),
            leftEyeCenter: leftEye,
            rightEyeCenter: rightEye,
            noseCenter: nil,
            faceConfidence: 1.0
        )

        let rois = ROIComputer.compute(face: face)
        XCTAssertNotNil(rois)
        XCTAssertEqual(rois?.eyeROIs.count, 1)

        guard let only = rois?.eyeROIs.first else { return }
        // The only remaining ROI should be for the right eye (midX closer to 0.65 than 0.35).
        XCTAssertEqual(only.midX, 0.65, accuracy: 0.08)
    }

    func testEyeROIs_areComputedIndependently_whenOneEyeFailsConfidenceGate() {
        // Fallback path when no precision estimates are available.
        let leftEye = VisionLandmark(pPortrait: CGPoint(x: 0.35, y: 0.45), confidence: 0.20, aspectRatioHeightOverWidth: 0.40, precisionEstimatesPerPoint: nil)
        let rightEye = VisionLandmark(pPortrait: CGPoint(x: 0.65, y: 0.45), confidence: 1.0, aspectRatioHeightOverWidth: 0.40, precisionEstimatesPerPoint: nil)

        let face = VisionFaceResult(
            faceBBoxPortrait: CGRect(x: 0.25, y: 0.25, width: 0.50, height: 0.50),
            leftEyeCenter: leftEye,
            rightEyeCenter: rightEye,
            noseCenter: nil,
            faceConfidence: 1.0
        )

        let rois = ROIComputer.compute(face: face)
        XCTAssertNotNil(rois)
        XCTAssertEqual(rois?.eyeROIs.count, 1)

        guard let only = rois?.eyeROIs.first else { return }
        XCTAssertEqual(only.midX, 0.65, accuracy: 0.08)
    }

    func testEyeROIs_includeBothEyes_whenBothPassGates() {
        let leftEye = VisionLandmark(pPortrait: CGPoint(x: 0.35, y: 0.45), confidence: nil, aspectRatioHeightOverWidth: 0.40, precisionEstimatesPerPoint: [0.007, 0.008])
        let rightEye = VisionLandmark(pPortrait: CGPoint(x: 0.65, y: 0.45), confidence: nil, aspectRatioHeightOverWidth: 0.40, precisionEstimatesPerPoint: [0.006, 0.009])

        let face = VisionFaceResult(
            faceBBoxPortrait: CGRect(x: 0.25, y: 0.25, width: 0.50, height: 0.50),
            leftEyeCenter: leftEye,
            rightEyeCenter: rightEye,
            noseCenter: nil,
            faceConfidence: 1.0
        )

        let rois = ROIComputer.compute(face: face)
        XCTAssertNotNil(rois)
        XCTAssertEqual(rois?.eyeROIs.count, 2)

        let midXs = (rois?.eyeROIs ?? []).map { $0.midX }.sorted()
        XCTAssertEqual(midXs[0], 0.35, accuracy: 0.08)
        XCTAssertEqual(midXs[1], 0.65, accuracy: 0.08)
    }
}
