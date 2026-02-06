import Foundation

// PRD 4.1.2: camera init failure reasons.
enum CameraInitFailureReason: String, Codable, Sendable {
    case permission_denied = "permission_denied"
    case camera_in_use = "camera_in_use"
    case hardware_unavailable = "hardware_unavailable"
    case unknown = "unknown"

    var explanationText: String {
        switch self {
        case .permission_denied:
            return "未获得相机权限"
        case .camera_in_use:
            return "相机可能被其他应用占用"
        case .hardware_unavailable:
            return "设备相机不可用"
        case .unknown:
            return "发生未知错误"
        }
    }
}

enum CameraInitFailureDebugSettings {
    static let simulatedFailureReasonKey = "debug_simulate_camera_init_failure_reason"

    static func simulatedFailureReason() -> CameraInitFailureReason? {
        guard let raw = UserDefaults.standard.string(forKey: simulatedFailureReasonKey) else { return nil }
        return CameraInitFailureReason(rawValue: raw)
    }

    static func setSimulatedFailureReason(_ reason: CameraInitFailureReason?) {
        if let reason {
            UserDefaults.standard.set(reason.rawValue, forKey: simulatedFailureReasonKey)
        } else {
            UserDefaults.standard.removeObject(forKey: simulatedFailureReasonKey)
        }
    }
}
