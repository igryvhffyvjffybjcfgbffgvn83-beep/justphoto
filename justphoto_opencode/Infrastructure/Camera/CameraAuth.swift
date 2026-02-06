import AVFoundation

// PRD 4.1.2 "CameraAuth" (camera permission state) for .video.
enum CameraAuth: String, Codable, Sendable {
    case not_determined = "not_determined"
    case authorized = "authorized"
    case denied = "denied"
    case restricted = "restricted"
}

enum CameraAuthMapper {
    static func map(_ status: AVAuthorizationStatus) -> CameraAuth {
        switch status {
        case .notDetermined:
            return .not_determined
        case .authorized:
            return .authorized
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        @unknown default:
            // Safe fallback: treat unknown as blocked.
            return .denied
        }
    }

    static func currentVideoAuth() -> CameraAuth {
        map(AVCaptureDevice.authorizationStatus(for: .video))
    }

    static func requestVideoAccess() async -> Bool {
        await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .video) { granted in
                continuation.resume(returning: granted)
            }
        }
    }
}
