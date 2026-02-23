import CoreGraphics
import CoreImage
import CoreVideo
import Foundation
import ImageIO

// M6.16 Phase 1: Extract target metric outputs from a static reference image.

struct RefTargetInput {
    let cgImage: CGImage
    let orientation: CGImagePropertyOrientation
}

struct RefTargetOutput {
    let metrics: [MetricKey: MetricOutput]
}

enum RefTargetExtractor {
    // Pure extraction: no shared state, no pixel persistence.
    static func extract(input: RefTargetInput) async -> RefTargetOutput? {
        guard let (pixelBuffer, effectiveOrientation) = RefTargetPixelBufferBuilder.make(
            from: input.cgImage,
            orientation: input.orientation
        ) else {
            return nil
        }

        let pipeline = VisionPipeline()
        let vision = await pipeline.process(pixelBuffer: pixelBuffer, orientation: effectiveOrientation)

        let pose = vision?.pose
        let face = vision?.face
        let rois = ROIComputer.compute(pose: pose, face: face)

        let metricComputer = MetricComputer.makeIsolated()
        let metrics = metricComputer.computeMetrics(
            context: MetricContext(
                pose: pose,
                face: face,
                rois: rois,
                pixelBuffer: pixelBuffer,
                orientation: effectiveOrientation
            )
        )

        return RefTargetOutput(metrics: metrics)
    }
}

private enum RefTargetPixelBufferBuilder {
    static func make(
        from cgImage: CGImage,
        orientation: CGImagePropertyOrientation
    ) -> (CVPixelBuffer, CGImagePropertyOrientation)? {
        let base = CIImage(cgImage: cgImage)
        let oriented: CIImage = {
            guard orientation != .up else { return base }
            return base.oriented(forExifOrientation: Int32(orientation.rawValue))
        }()

        let extent = oriented.extent.integral
        var width = Int(extent.width)
        var height = Int(extent.height)
        if width % 2 != 0 { width -= 1 }
        if height % 2 != 0 { height -= 1 }
        guard width > 0, height > 0 else { return nil }

        let renderRect = CGRect(
            x: extent.origin.x,
            y: extent.origin.y,
            width: CGFloat(width),
            height: CGFloat(height)
        )

        let attrs: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
            kCVPixelBufferIOSurfacePropertiesKey: [:],
        ]

        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
            attrs as CFDictionary,
            &pixelBuffer
        )
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
            return nil
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CIContext(options: [.workingColorSpace: colorSpace])
        let cropped = oriented.cropped(to: renderRect)
        context.render(cropped, to: buffer, bounds: renderRect, colorSpace: colorSpace)

        // After orientation is applied to pixel data, Vision can treat it as .up.
        return (buffer, .up)
    }
}
