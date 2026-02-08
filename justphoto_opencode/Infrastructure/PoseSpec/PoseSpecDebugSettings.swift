import Foundation

enum PoseSpecDebugSettings {
    private static let keyUseBrokenOnce = "justphoto.debug.posespec.use_broken_once"
    private static let keyUseWrongPrdOnce = "justphoto.debug.posespec.use_wrong_prd_once"
    private static let keyUseMissingAliasOnce = "justphoto.debug.posespec.use_missing_alias_once"
    private static let keyUseMissingEyeROIOnce = "justphoto.debug.posespec.use_missing_eye_roi_once"

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

    static func armUseMissingAliasOnce() {
        UserDefaults.standard.set(true, forKey: keyUseMissingAliasOnce)
    }

    static func consumeUseMissingAliasOnce() -> Bool {
        let v = UserDefaults.standard.bool(forKey: keyUseMissingAliasOnce)
        if v {
            UserDefaults.standard.set(false, forKey: keyUseMissingAliasOnce)
        }
        return v
    }

    static func armUseMissingEyeROIOnce() {
        UserDefaults.standard.set(true, forKey: keyUseMissingEyeROIOnce)
    }

    static func consumeUseMissingEyeROIOnce() -> Bool {
        let v = UserDefaults.standard.bool(forKey: keyUseMissingEyeROIOnce)
        if v {
            UserDefaults.standard.set(false, forKey: keyUseMissingEyeROIOnce)
        }
        return v
    }

#if DEBUG
    static func debugIsMissingAliasArmed() -> Bool {
        UserDefaults.standard.bool(forKey: keyUseMissingAliasOnce)
    }

    static func debugIsWrongPrdArmed() -> Bool {
        UserDefaults.standard.bool(forKey: keyUseWrongPrdOnce)
    }

    static func debugIsBrokenPoseSpecArmed() -> Bool {
        UserDefaults.standard.bool(forKey: keyUseBrokenOnce)
    }

    static func debugIsMissingEyeROIArmed() -> Bool {
        UserDefaults.standard.bool(forKey: keyUseMissingEyeROIOnce)
    }
#endif
}
