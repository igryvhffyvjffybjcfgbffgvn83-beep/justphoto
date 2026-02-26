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

    struct PhotoCaptureResult: Sendable {
        let data: Data
        let fileExtension: String
    }

    enum PhotoCaptureError: Error {
        case cameraNotRunning
        case missingOutput
        case fileDataMissing
        case captureFailed(String)
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

    private let photoOutputQueue = DispatchQueue(label: "justphoto.camera.photo_output")
    private let photoOutput = AVCapturePhotoOutput()

    nonisolated(unsafe) private var lastDeliveredTsMs: Int = 0

#if canImport(UIKit)
    private static let latestInstanceLock = NSLock()
    private static weak var latestInstance: CameraFrameSource?
#endif

#if canImport(UIKit)
    private var orientationObserver: NSObjectProtocol? = nil
    private let interfaceOrientationLock = NSLock()
    nonisolated(unsafe) private var cachedInterfaceOrientation: UIInterfaceOrientation? = nil

    private let photoDelegatesLock = NSLock()
    private var inFlightPhotoDelegates: [UUID: PhotoCaptureDelegate] = [:]
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
#if canImport(UIKit)
            Self.setLatestInstance(self)
#endif
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
        Self.clearLatestInstance(self)
#endif
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

        guard session.canAddOutput(photoOutput) else {
            throw NSError(domain: "CameraFrameSource", code: 4, userInfo: [NSLocalizedDescriptionKey: "Cannot add photo output"])
        }
        session.addOutput(photoOutput)
        photoOutput.isHighResolutionCaptureEnabled = true
        photoOutput.maxPhotoQualityPrioritization = .quality
        if let c = photoOutput.connection(with: .video) {
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
        let mirrored = connection.isVideoMirrored || isFrontCamera
        let cgOrientation: CGImagePropertyOrientation
        if connection.isVideoOrientationSupported {
            switch connection.videoOrientation {
            case .portrait:
                cgOrientation = mirrored ? .leftMirrored : .right
            case .portraitUpsideDown:
                cgOrientation = mirrored ? .rightMirrored : .left
            case .landscapeRight:
                cgOrientation = mirrored ? .upMirrored : .down
            case .landscapeLeft:
                cgOrientation = mirrored ? .downMirrored : .up
            @unknown default:
                cgOrientation = mirrored ? .leftMirrored : .right
            }
        } else {
            switch getCachedInterfaceOrientation() {
            case .portrait:
                cgOrientation = isFrontCamera ? .leftMirrored : .right
            case .portraitUpsideDown:
                cgOrientation = isFrontCamera ? .rightMirrored : .left
            case .landscapeLeft:
                cgOrientation = isFrontCamera ? .downMirrored : .up
            case .landscapeRight:
                cgOrientation = isFrontCamera ? .upMirrored : .down
            default:
                cgOrientation = isFrontCamera ? .leftMirrored : .right
            }
        }
        #else
        let cgOrientation: CGImagePropertyOrientation = isFrontCamera ? .upMirrored : .up
        #endif

        onFrame?(pixelBuffer, cgOrientation)
    }
}

#if canImport(UIKit)
extension CameraFrameSource {
    static func capturePhotoDataFromActive() async throws -> PhotoCaptureResult {
        guard let instance = getLatestInstance() else {
            throw PhotoCaptureError.cameraNotRunning
        }
        return try await instance.capturePhotoData()
    }

    private static func getLatestInstance() -> CameraFrameSource? {
        latestInstanceLock.lock()
        defer { latestInstanceLock.unlock() }
        return latestInstance
    }

    private static func setLatestInstance(_ instance: CameraFrameSource) {
        latestInstanceLock.lock()
        latestInstance = instance
        latestInstanceLock.unlock()
    }

    private static func clearLatestInstance(_ instance: CameraFrameSource) {
        latestInstanceLock.lock()
        if latestInstance === instance {
            latestInstance = nil
        }
        latestInstanceLock.unlock()
    }

    private final class PhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate {
        let id: UUID
        let completion: (Result<Data, Error>) -> Void

        init(id: UUID, completion: @escaping (Result<Data, Error>) -> Void) {
            self.id = id
            self.completion = completion
        }

        func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
            if let error {
                completion(.failure(error))
                return
            }
            guard let data = photo.fileDataRepresentation() else {
                completion(.failure(PhotoCaptureError.fileDataMissing))
                return
            }
            completion(.success(data))
        }
    }

    private func capturePhotoData() async throws -> PhotoCaptureResult {
        guard state == .running else {
            throw PhotoCaptureError.cameraNotRunning
        }

        let codec: AVVideoCodecType
        if photoOutput.availablePhotoCodecTypes.contains(.hevc) {
            codec = .hevc
        } else if photoOutput.availablePhotoCodecTypes.contains(.jpeg) {
            codec = .jpeg
        } else {
            throw PhotoCaptureError.missingOutput
        }

        let settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: codec])
        settings.photoQualityPrioritization = .quality
        if photoOutput.isHighResolutionCaptureEnabled {
            settings.isHighResolutionPhotoEnabled = true
        }

        let data: Data = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            let id = UUID()
            let delegate = PhotoCaptureDelegate(id: id) { [weak self] result in
                guard let self else {
                    continuation.resume(throwing: PhotoCaptureError.captureFailed("CameraFrameSource deallocated"))
                    return
                }
                self.removeInFlightDelegate(id: id)
                switch result {
                case .success(let data):
                    continuation.resume(returning: data)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
            addInFlightDelegate(delegate)
            photoOutputQueue.async { [weak self] in
                guard let self else { return }
                self.photoOutput.capturePhoto(with: settings, delegate: delegate)
            }
        }

        let fileExtension = (codec == .hevc) ? "heic" : "jpg"
        return PhotoCaptureResult(data: data, fileExtension: fileExtension)
    }

    private func addInFlightDelegate(_ delegate: PhotoCaptureDelegate) {
        photoDelegatesLock.lock()
        inFlightPhotoDelegates[delegate.id] = delegate
        photoDelegatesLock.unlock()
    }

    private func removeInFlightDelegate(id: UUID) {
        photoDelegatesLock.lock()
        inFlightPhotoDelegates.removeValue(forKey: id)
        photoDelegatesLock.unlock()
    }
}

extension CameraFrameSource {
    nonisolated private func getCachedInterfaceOrientation() -> UIInterfaceOrientation? {
        interfaceOrientationLock.lock()
        defer { interfaceOrientationLock.unlock() }
        return cachedInterfaceOrientation
    }

    nonisolated private func setCachedInterfaceOrientation(_ v: UIInterfaceOrientation?) {
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
