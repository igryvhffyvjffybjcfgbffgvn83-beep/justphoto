import Foundation

enum PoseSpecDebugSettings {
    private static let keyUseBrokenOnce = "justphoto.debug.posespec.use_broken_once"

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
}
