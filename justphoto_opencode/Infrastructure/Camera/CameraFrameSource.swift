import AVFoundation
import Combine
import Foundation
import ImageIO

#if canImport(UIKit)
import UIKit
#endif

final class CameraFrameSource: NSObject, ObservableObject {
    enum State: String {
        case idle
        case running
        case failed
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var lastError: String? = nil

    let session = AVCaptureSession()

    // Updated during configureIfNeeded.
    nonisolated(unsafe) private var isFrontCamera: Bool = false

    // Deliver frames at most once per interval.
    nonisolated(unsafe) var minFrameIntervalMs: Int = 100

    nonisolated(unsafe) var onFrame: ((CVPixelBuffer, CGImagePropertyOrientation) -> Void)?

    private let outputQueue = DispatchQueue(label: "justphoto.camera.frame_output")
    private let videoOutput = AVCaptureVideoDataOutput()

    nonisolated(unsafe) private var lastDeliveredTsMs: Int = 0

#if canImport(UIKit)
    private var orientationObserver: NSObjectProtocol? = nil
    private let interfaceOrientationLock = NSLock()
    nonisolated(unsafe) private var cachedInterfaceOrientation: UIInterfaceOrientation? = nil
#endif

    func start() {
        if state == .running { return }

        do {
            try configureIfNeeded()

#if canImport(UIKit)
            setCachedInterfaceOrientation(currentInterfaceOrientation())
            if orientationObserver == nil {
                orientationObserver = NotificationCenter.default.addObserver(
                    forName: UIDevice.orientationDidChangeNotification,
                    object: nil,
                    queue: .main
                ) { [weak self] _ in
                    guard let self else { return }
                    self.setCachedInterfaceOrientation(self.currentInterfaceOrientation())
                }
            }
#endif

            session.startRunning()
            DispatchQueue.main.async {
                self.state = .running
                self.lastError = nil
            }
            #if DEBUG
            print("CameraFrameSourceStarted")
            #endif
        } catch {
            DispatchQueue.main.async {
                self.state = .failed
                self.lastError = String(describing: error)
            }
            #if DEBUG
            print("CameraFrameSourceStartFAILED: \(error)")
            #endif
        }
    }

    func stop() {
        guard state == .running else {
            DispatchQueue.main.async { self.state = .idle }
            return
        }
        session.stopRunning()
        DispatchQueue.main.async { self.state = .idle }

#if canImport(UIKit)
        if let obs = orientationObserver {
            NotificationCenter.default.removeObserver(obs)
            orientationObserver = nil
        }
#endif
        #if DEBUG
        print("CameraFrameSourceStopped")
        #endif
    }

    private func configureIfNeeded() throws {
        if session.inputs.isEmpty == false {
            return
        }

        session.beginConfiguration()
        defer { session.commitConfiguration() }

        session.sessionPreset = .high

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            throw NSError(domain: "CameraFrameSource", code: 1, userInfo: [NSLocalizedDescriptionKey: "No camera device"])
        }

        isFrontCamera = (device.position == .front)

        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else {
            throw NSError(domain: "CameraFrameSource", code: 2, userInfo: [NSLocalizedDescriptionKey: "Cannot add camera input"])
        }
        session.addInput(input)

        videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange]
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.setSampleBufferDelegate(self, queue: outputQueue)

        guard session.canAddOutput(videoOutput) else {
            throw NSError(domain: "CameraFrameSource", code: 3, userInfo: [NSLocalizedDescriptionKey: "Cannot add video output"])
        }
        session.addOutput(videoOutput)

        if let c = videoOutput.connection(with: .video) {
            c.videoOrientation = .portrait
        }
    }
}

extension CameraFrameSource: AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let tsMs = Int(Date().timeIntervalSince1970 * 1000)
        let minInterval = max(0, minFrameIntervalMs)
        if tsMs - lastDeliveredTsMs < minInterval {
            return
        }
        lastDeliveredTsMs = tsMs

#if canImport(UIKit)
        let cgOrientation: CGImagePropertyOrientation
        switch getCachedInterfaceOrientation() {
        case .portrait:
            // AVCaptureVideoDataOutput pixel buffers are typically delivered in the camera sensor
            // orientation (landscape). For Vision, we must provide the EXIF orientation that
            // describes how to rotate the buffer into the UI's portrait-up space.
            // NOTE: Empirically, our pipeline expects the opposite 90deg for this device class;
            // using `.right` here results in a 180deg error after normalization (bottom-right -> top-left).
            // So we use `.left` for back camera portrait.
            cgOrientation = isFrontCamera ? .rightMirrored : .left
        case .portraitUpsideDown:
            cgOrientation = isFrontCamera ? .leftMirrored : .right
        case .landscapeLeft:
            cgOrientation = isFrontCamera ? .downMirrored : .down
        case .landscapeRight:
            cgOrientation = isFrontCamera ? .upMirrored : .up
        default:
            cgOrientation = isFrontCamera ? .rightMirrored : .left
        }
        #else
        let cgOrientation: CGImagePropertyOrientation = isFrontCamera ? .upMirrored : .up
        #endif

        onFrame?(pixelBuffer, cgOrientation)
    }
}

#if canImport(UIKit)
extension CameraFrameSource {
    private func getCachedInterfaceOrientation() -> UIInterfaceOrientation? {
        interfaceOrientationLock.lock()
        defer { interfaceOrientationLock.unlock() }
        return cachedInterfaceOrientation
    }

    private func setCachedInterfaceOrientation(_ v: UIInterfaceOrientation?) {
        interfaceOrientationLock.lock()
        defer { interfaceOrientationLock.unlock() }
        cachedInterfaceOrientation = v
    }

    private func currentInterfaceOrientation() -> UIInterfaceOrientation? {
        let scenes = UIApplication.shared.connectedScenes
        let ws = scenes.compactMap { $0 as? UIWindowScene }
        return ws.first?.interfaceOrientation
    }

}
#endif
