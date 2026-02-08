import Foundation

enum PoseSpecDebugSettings {
    private static let keyUseBrokenOnce = "justphoto.debug.posespec.use_broken_once"
    private static let keyUseWrongPrdOnce = "justphoto.debug.posespec.use_wrong_prd_once"

    static func armUseBrokenPoseSpecOnce() {
        UserDefaults.standard.set(true, forKey: keyUseBrokenOnce)
    }

    static func consumeUseBrokenPoseSpecOnce() -> Bool {
        let v = UserDefaults.standard.bool(forKey: keyUseBrokenOnce)
        if v {
            UserDefaults.standard.set(false, forKey: keyUseBrokenOnce)
        }
        return v
    }

    static func armUseWrongPrdVersionOnce() {
        UserDefaults.standard.set(true, forKey: keyUseWrongPrdOnce)
    }

    static func consumeUseWrongPrdVersionOnce() -> Bool {
        let v = UserDefaults.standard.bool(forKey: keyUseWrongPrdOnce)
        if v {
            UserDefaults.standard.set(false, forKey: keyUseWrongPrdOnce)
        }
        return v
    }
}
