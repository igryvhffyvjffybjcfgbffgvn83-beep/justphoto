import Foundation
#if canImport(UIKit)
import UIKit
#endif
import ImageIO

// M6.7: Centralized orientation mapping for Vision/metrics normalization.
enum PoseSpecOrientation {
    #if canImport(UIKit)
    static func currentInterfaceOrientation() -> UIInterfaceOrientation? {
        let scenes = UIApplication.shared.connectedScenes
        let ws = scenes.compactMap { $0 as? UIWindowScene }
        return ws.first?.interfaceOrientation
    }
    #endif

    // Best-effort mapping from interface orientation + camera facing to a CGImagePropertyOrientation
    // suitable for point normalization to portrait space.
    //
    // Note: the real camera pipeline will provide authoritative pixel buffer orientation.
    static func cgImageOrientation(interface: Any?, isFrontCamera: Bool) -> CGImagePropertyOrientation {
        #if canImport(UIKit)
        if let io = interface as? UIInterfaceOrientation {
            switch io {
            case .portrait:
                return isFrontCamera ? .upMirrored : .up
            case .portraitUpsideDown:
                return isFrontCamera ? .downMirrored : .down
            case .landscapeLeft:
                // Home button/right side.
                return isFrontCamera ? .rightMirrored : .right
            case .landscapeRight:
                return isFrontCamera ? .leftMirrored : .left
            default:
                return isFrontCamera ? .upMirrored : .up
            }
        }
        #endif
        _ = interface
        return isFrontCamera ? .upMirrored : .up
    }
}
