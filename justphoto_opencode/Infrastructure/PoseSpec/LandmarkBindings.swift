import Foundation
import Vision

// M6.10 Phase 1: Binding contract between Vision joints and PoseSpec landmark keys.
//
// PoseSpec (v1.1.4) expects pose joints under the `body.*` namespace.
// Aliases like `lShoulder` live in PoseSpec.json and are resolved at evaluation time.
// This file provides a deterministic mapping from Vision joint names -> canonical `body.*` keys,
// plus a small alias mapping used for debug dumps.

enum PoseSpecAlias: String, CaseIterable, Sendable {
    // Required by PoseSpecValidator.validateBindingAliasesMinimalSet
    case lShoulder
    case rShoulder
    case lHip
    case rHip
    case lAnkle
    case rAnkle
    case faceBBox
    case noseTip
    case chinCenter
    case lEye
    case rEye
    case eyeMid
    case hipMid
    case ankleMid
}

enum LandmarkBindings {
    // Stable ordered extraction list for Phase 1 logging.
    // Keep this list small and deterministic to avoid log noise.
    static let orderedBodyJoints: [VNHumanBodyPoseObservation.JointName] = [
        .nose,
        .neck,
        .leftShoulder,
        .rightShoulder,
        .leftHip,
        .rightHip,
        .leftAnkle,
        .rightAnkle,
        .leftEye,
        .rightEye,
        .leftWrist,
        .rightWrist,
    ]

    // Canonical PoseSpec `metric.landmarks` keys for pose joints.
    // NOTE: these must match PoseSpec.json `binding.sets.bodyPoints.include = "body.*"`.
    static let bodyJointToCanonicalKey: [VNHumanBodyPoseObservation.JointName: String] = {
        var m: [VNHumanBodyPoseObservation.JointName: String] = [:]
        for j in orderedBodyJoints {
            // `String(describing:)` for JointName yields the PoseSpec token (e.g. "leftShoulder").
            m[j] = "body." + String(describing: j)
        }
        return m
    }()

    // Optional alias mapping used only for debug dumps.
    // PoseSpec's true alias->path mapping remains the source of truth in PoseSpec.json.
    static let bodyJointToDebugAlias: [VNHumanBodyPoseObservation.JointName: PoseSpecAlias] = [
        .leftShoulder: .lShoulder,
        .rightShoulder: .rShoulder,
        .leftHip: .lHip,
        .rightHip: .rHip,
        .leftAnkle: .lAnkle,
        .rightAnkle: .rAnkle,

        // Phase 1 convenience mapping: treat pose `nose` as `noseTip` for logging.
        // (PoseSpec.json defines noseTip under face.*; Phase 2+ will reconcile.)
        .nose: .noseTip,
        .leftEye: .lEye,
        .rightEye: .rEye,
    ]
}
