import XCTest
import CoreGraphics
import ImageIO

@testable import justphoto_opencode

final class CoordinateTests: XCTestCase {
    func testVisionYUpToCanonicalYDown_up() {
        // Vision normalized coordinates are typically Y-Up (origin bottom-left).
        // Input (0.1, 0.1) is near the bottom-left; canonical Y-Down should flip to (0.1, 0.9).
        let vision = CGPoint(x: 0.1, y: 0.1)
        let out = PoseSpecCoordinateNormalizer.normalize(vision, sourceOrientation: .up)
        XCTAssertEqual(out.x, 0.1, accuracy: 1e-6)
        XCTAssertEqual(out.y, 0.9, accuracy: 1e-6)
    }

    func testOrientationAndMirrorMappings() {
        let p = CGPoint(x: 0.2, y: 0.3)

        // Orientation/mirroring is handled by Vision when the request is performed with the
        // correct EXIF orientation. The normalizer's job is only Vision Y-Up -> canonical Y-Down.
        let cases: [CGImagePropertyOrientation] = [
            .up,
            .down,
            .left,
            .right,
            .upMirrored,
            .downMirrored,
            .leftMirrored,
            .rightMirrored,
        ]

        let expected = CGPoint(x: 0.2, y: 0.7)

        for o in cases {
            let out = PoseSpecCoordinateNormalizer.normalize(p, sourceOrientation: o)
            XCTAssertEqual(out.x, expected.x, accuracy: 1e-6, "orientation=\(o.rawValue) x")
            XCTAssertEqual(out.y, expected.y, accuracy: 1e-6, "orientation=\(o.rawValue) y")
        }
    }
}
