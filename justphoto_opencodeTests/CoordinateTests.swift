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

        // Expected values are locked to PoseSpecCoordinateNormalizer's contract:
        // - First map to portrait `.up` (Vision native Y-Up)
        // - Then flip into canonical Y-Down
        let cases: [(CGImagePropertyOrientation, CGPoint)] = [
            (.up, CGPoint(x: 0.2, y: 0.7)),
            (.down, CGPoint(x: 0.8, y: 0.3)),
            (.left, CGPoint(x: 0.3, y: 0.2)),
            (.right, CGPoint(x: 0.7, y: 0.8)),
            (.upMirrored, CGPoint(x: 0.8, y: 0.7)),
            (.downMirrored, CGPoint(x: 0.2, y: 0.3)),
            (.leftMirrored, CGPoint(x: 0.7, y: 0.2)),
            (.rightMirrored, CGPoint(x: 0.3, y: 0.8)),
        ]

        for (o, expected) in cases {
            let out = PoseSpecCoordinateNormalizer.normalize(p, sourceOrientation: o)
            XCTAssertEqual(out.x, expected.x, accuracy: 1e-6, "orientation=\(o.rawValue) x")
            XCTAssertEqual(out.y, expected.y, accuracy: 1e-6, "orientation=\(o.rawValue) y")
        }
    }
}
