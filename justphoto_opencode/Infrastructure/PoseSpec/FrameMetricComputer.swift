import Accelerate
import CoreGraphics
import CoreVideo
import Foundation

// M6.10 Phase 4: Pixel-level metrics computed from CVPixelBuffer using Accelerate.
final class FrameMetricComputer {
    private let minInterval: CFTimeInterval = 0.5
    private var lastRunTime: CFTimeInterval = 0
    #if DEBUG
    private var throttleCount: Int = 0
    #endif

    func computeFaceLumaMean(pixelBuffer: CVPixelBuffer, faceROI: CGRect) -> Double? {
        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastRunTime >= minInterval else {
            #if DEBUG
            throttleCount += 1
            if throttleCount % 30 == 0 {
                print("T1 Throttled")
            }
            #endif
            return nil
        }
        lastRunTime = now
        #if DEBUG
        throttleCount = 0
        #endif

        guard !faceROI.isNull, !faceROI.isEmpty else { return nil }

        let format = CVPixelBufferGetPixelFormatType(pixelBuffer)
        let isBiPlanar = (format == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange) ||
            (format == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange)
        guard isBiPlanar else { return nil }

        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        let plane = 0
        guard let baseAddress = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, plane) else { return nil }

        let width = CVPixelBufferGetWidthOfPlane(pixelBuffer, plane)
        let height = CVPixelBufferGetHeightOfPlane(pixelBuffer, plane)
        let rowBytes = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, plane)

        guard width > 1, height > 1 else { return nil }

        guard let roiRect = pixelRect(from: faceROI, width: width, height: height) else { return nil }

        let offset = roiRect.y * rowBytes + roiRect.x
        let roiBase = baseAddress.advanced(by: offset)
        var buffer = vImage_Buffer(
            data: roiBase,
            height: vImagePixelCount(roiRect.h),
            width: vImagePixelCount(roiRect.w),
            rowBytes: rowBytes
        )

        var histogram = [vImagePixelCount](repeating: 0, count: 256)
        let err = histogram.withUnsafeMutableBufferPointer { buf -> vImage_Error in
            guard let base = buf.baseAddress else { return kvImageNullPointerArgument }
            return vImageHistogramCalculation_Planar8(&buffer, base, vImage_Flags(kvImageNoFlags))
        }
        guard err == kvImageNoError else { return nil }

        var total: Double = 0
        var sum: Double = 0
        for i in 0..<256 {
            let c = Double(histogram[i])
            total += c
            sum += Double(i) * c
        }
        guard total > 0 else { return nil }

        return (sum / total) / 255.0
    }

    private struct PixelRect {
        let x: Int
        let y: Int
        let w: Int
        let h: Int
    }

    private func pixelRect(from roi: CGRect, width: Int, height: Int) -> PixelRect? {
        let clamped = clampNormalized(roi)
        guard !clamped.isNull, !clamped.isEmpty else { return nil }

        let wF = CGFloat(width)
        let hF = CGFloat(height)

        let x0 = Int((clamped.minX * wF).rounded(.down))
        let y0 = Int((clamped.minY * hF).rounded(.down))
        let x1 = Int((clamped.maxX * wF).rounded(.up))
        let y1 = Int((clamped.maxY * hF).rounded(.up))

        let x = max(0, min(width - 1, x0))
        let y = max(0, min(height - 1, y0))
        let xEnd = max(x + 1, min(width, x1))
        let yEnd = max(y + 1, min(height, y1))

        let w = xEnd - x
        let h = yEnd - y
        guard w > 1, h > 1 else { return nil }

        return PixelRect(x: x, y: y, w: w, h: h)
    }

    private func clampNormalized(_ r: CGRect) -> CGRect {
        let unit = CGRect(x: 0, y: 0, width: 1, height: 1)
        let s = r.standardized
        let inter = s.intersection(unit)
        if inter.isNull || inter.isEmpty {
            return .null
        }
        return inter
    }
}
