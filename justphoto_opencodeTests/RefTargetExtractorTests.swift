import XCTest
import CoreGraphics
import ImageIO

@testable import justphoto_opencode

final class RefTargetExtractorTests: XCTestCase {
    func testRefTargetExtractor_isDeterministic() async throws {
        let image = makePatternImage(width: 64, height: 64)
        let input = RefTargetInput(cgImage: image, orientation: .up)

        let first = await RefTargetExtractor.extract(input: input)
        let second = await RefTargetExtractor.extract(input: input)

        XCTAssertNotNil(first)
        XCTAssertNotNil(second)

        guard let first, let second else { return }
        assertMetricsEqual(first.metrics, second.metrics, accuracy: 1e-3)
    }

    func testRefTargetExtractor_handlesMissingLandmarks() async throws {
        let image = makeSolidImage(width: 8, height: 8, gray: 0x80)
        let input = RefTargetInput(cgImage: image, orientation: .up)

        let output = await RefTargetExtractor.extract(input: input)
        XCTAssertNotNil(output)

        guard let output else { return }
        let metrics = output.metrics

        XCTAssertEqual(metrics[.centerXOffset]?.value, nil)
        XCTAssertEqual(metrics[.centerXOffset]?.reason, .missingLandmark)
        XCTAssertEqual(metrics[.eyeLineAngleDeg]?.value, nil)
        XCTAssertEqual(metrics[.eyeLineAngleDeg]?.reason, .missingLandmark)
        XCTAssertEqual(metrics[.faceLumaMean]?.value, nil)
        XCTAssertEqual(metrics[.faceLumaMean]?.reason, .missingLandmark)
    }

    private func assertMetricsEqual(
        _ lhs: [MetricKey: MetricOutput],
        _ rhs: [MetricKey: MetricOutput],
        accuracy: Double,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(Set(lhs.keys), Set(rhs.keys), file: file, line: line)

        let keys = Set(lhs.keys).union(rhs.keys)
        for key in keys {
            guard let lv = lhs[key], let rv = rhs[key] else {
                XCTFail("Missing metric output for key \(key)", file: file, line: line)
                continue
            }

            switch (lv.value, rv.value) {
            case let (l?, r?):
                XCTAssertEqual(l, r, accuracy: accuracy, "key=\(key)", file: file, line: line)
            case (nil, nil):
                XCTAssertEqual(lv.reason, rv.reason, "key=\(key)", file: file, line: line)
            default:
                XCTFail("Mismatched availability for key \(key)", file: file, line: line)
            }
        }
    }

    private func makePatternImage(width: Int, height: Int) -> CGImage {
        let data = makeRGBAData(width: width, height: height) { x, y in
            let v = UInt8((x &* 31 &+ y &* 17) & 0xFF)
            return (v, 255 &- v, v ^ 0xAA, 0xFF)
        }
        return makeImage(width: width, height: height, data: data)
    }

    private func makeSolidImage(width: Int, height: Int, gray: UInt8) -> CGImage {
        let data = makeRGBAData(width: width, height: height) { _, _ in
            (gray, gray, gray, 0xFF)
        }
        return makeImage(width: width, height: height, data: data)
    }

    private func makeRGBAData(
        width: Int,
        height: Int,
        pixel: (Int, Int) -> (UInt8, UInt8, UInt8, UInt8)
    ) -> Data {
        let count = width * height * 4
        var bytes = [UInt8](repeating: 0, count: count)

        var idx = 0
        for y in 0..<height {
            for x in 0..<width {
                let (r, g, b, a) = pixel(x, y)
                bytes[idx] = r
                bytes[idx + 1] = g
                bytes[idx + 2] = b
                bytes[idx + 3] = a
                idx += 4
            }
        }

        return Data(bytes)
    }

    private func makeImage(width: Int, height: Int, data: Data) -> CGImage {
        let bytesPerRow = width * 4
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        let provider = CGDataProvider(data: data as CFData)

        guard let cgImage = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo,
            provider: provider!,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        ) else {
            XCTFail("Failed to create CGImage for tests")
            return CGImage(
                width: 1,
                height: 1,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: 4,
                space: colorSpace,
                bitmapInfo: bitmapInfo,
                provider: CGDataProvider(data: Data([0, 0, 0, 255]) as CFData)!,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
            )!
        }

        return cgImage
    }
}
