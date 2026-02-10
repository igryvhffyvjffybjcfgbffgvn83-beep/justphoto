import Foundation

// M6.10 Phase 1: Metric contract extracted from PoseSpec v1.1.4.
// This file defines the strongly-typed set of metric keys we must support,
// plus each metric's input dependencies (T0 vs T1, landmarks/frame/ROIs/etc).

enum MetricTier: String, Sendable {
    case t0
    case t1
}

struct MetricInputs: OptionSet, Sendable {
    let rawValue: UInt16

    static let poseLandmarks = MetricInputs(rawValue: 1 << 0)
    static let faceLandmarks = MetricInputs(rawValue: 1 << 1)
    static let pixelBuffer = MetricInputs(rawValue: 1 << 2)
    static let deviceMotion = MetricInputs(rawValue: 1 << 3)

    static let frameLines = MetricInputs(rawValue: 1 << 4)
    static let framePeople = MetricInputs(rawValue: 1 << 5)
    static let frameWhiteBalance = MetricInputs(rawValue: 1 << 6)

    static let refRegistration = MetricInputs(rawValue: 1 << 7)
}

enum MetricROI: String, Sendable, CaseIterable {
    case faceROI
    case eyeROI
    case bgROI
    case faceLeftHalf
    case faceRightHalf
    case upperBGROI
    case skyROI

    // PoseSpec uses a mixed-case token here.
    case bgRingROI = "BG_Ring_ROI"
}

struct MetricContract: Sendable {
    let tier: MetricTier
    let inputs: MetricInputs
    let roisUsed: Set<MetricROI>
}

// IMPORTANT:
// - Raw values are the PoseSpec identifiers (string-exact).
// - This list is extracted from PoseSpec v1.1.4 cues.
enum MetricKey: String, CaseIterable, Sendable {
    case avgConf
    case bboxHeight
    case bgLumaMean
    case bottomMargin
    case centerXOffset
    case centerYOffset
    case clip
    case colorTempK
    case colorTempLeftK
    case colorTempRightK
    case diff
    case distToThird
    case edgeDensityBG
    case extraPersonCount
    case eyeAR
    case eyeLineAngleDeg
    case faceHalfDiff
    case faceLumaMean
    case gap
    case headroom
    case hipAngleDeg
    case horizonAngleDeg
    case lumaRatio
    case minDistRatio
    case minElbowAngleDeg
    case motionRms
    case neckGap
    case noseToChinRatio
    case offset
    case ratio
    case registrationOffsetX
    case registrationOffsetY
    case registrationRotationDeg
    case registrationScale
    case shoulderAngleDeg
    case torsoLeanAngleDeg
    case verticalConvergeDeg
}

enum MetricContractBook {
    // Generated from `memory-bank/PoseSpec.json` (prdVersion=v1.1.4).
    static let contracts: [MetricKey: MetricContract] = [
        .avgConf: .init(tier: .t0, inputs: [.faceLandmarks], roisUsed: []),
        .bboxHeight: .init(tier: .t0, inputs: [.poseLandmarks], roisUsed: []),
        .bgLumaMean: .init(tier: .t1, inputs: [.faceLandmarks, .pixelBuffer], roisUsed: [.bgROI, .faceROI]),
        .bottomMargin: .init(tier: .t0, inputs: [.poseLandmarks], roisUsed: []),
        .centerXOffset: .init(tier: .t0, inputs: [.poseLandmarks], roisUsed: []),
        .centerYOffset: .init(tier: .t0, inputs: [.poseLandmarks], roisUsed: []),
        .clip: .init(tier: .t1, inputs: [.faceLandmarks, .pixelBuffer], roisUsed: [.eyeROI, .faceROI, .skyROI, .upperBGROI]),
        .colorTempK: .init(tier: .t1, inputs: [.faceLandmarks, .frameWhiteBalance], roisUsed: []),
        .colorTempLeftK: .init(tier: .t1, inputs: [.faceLandmarks, .frameWhiteBalance], roisUsed: []),
        .colorTempRightK: .init(tier: .t1, inputs: [.faceLandmarks, .frameWhiteBalance], roisUsed: []),
        .diff: .init(tier: .t1, inputs: [.faceLandmarks, .pixelBuffer], roisUsed: [.eyeROI, .faceROI]),
        .distToThird: .init(tier: .t0, inputs: [.poseLandmarks], roisUsed: []),
        .edgeDensityBG: .init(tier: .t1, inputs: [.faceLandmarks, .pixelBuffer], roisUsed: [.bgRingROI]),
        .extraPersonCount: .init(tier: .t1, inputs: [.framePeople], roisUsed: []),
        .eyeAR: .init(tier: .t0, inputs: [.faceLandmarks], roisUsed: []),
        .eyeLineAngleDeg: .init(tier: .t0, inputs: [.faceLandmarks], roisUsed: []),
        .faceHalfDiff: .init(tier: .t1, inputs: [.faceLandmarks, .pixelBuffer], roisUsed: [.faceLeftHalf, .faceRightHalf]),
        .faceLumaMean: .init(tier: .t1, inputs: [.faceLandmarks, .pixelBuffer], roisUsed: [.faceROI]),
        .gap: .init(tier: .t0, inputs: [.poseLandmarks, .faceLandmarks], roisUsed: []),
        .headroom: .init(tier: .t0, inputs: [.poseLandmarks], roisUsed: []),
        .hipAngleDeg: .init(tier: .t0, inputs: [.poseLandmarks], roisUsed: []),
        .horizonAngleDeg: .init(tier: .t1, inputs: [.frameLines], roisUsed: []),
        .lumaRatio: .init(tier: .t1, inputs: [.faceLandmarks, .pixelBuffer], roisUsed: [.bgROI, .faceROI]),
        .minDistRatio: .init(tier: .t0, inputs: [.poseLandmarks, .faceLandmarks], roisUsed: []),
        .minElbowAngleDeg: .init(tier: .t0, inputs: [.poseLandmarks], roisUsed: []),
        .motionRms: .init(tier: .t1, inputs: [.deviceMotion], roisUsed: []),
        .neckGap: .init(tier: .t0, inputs: [.poseLandmarks], roisUsed: []),
        .noseToChinRatio: .init(tier: .t0, inputs: [.faceLandmarks], roisUsed: []),
        .offset: .init(tier: .t0, inputs: [.poseLandmarks], roisUsed: []),
        .ratio: .init(tier: .t0, inputs: [.poseLandmarks], roisUsed: []),
        .registrationOffsetX: .init(tier: .t1, inputs: [.refRegistration], roisUsed: []),
        .registrationOffsetY: .init(tier: .t1, inputs: [.refRegistration], roisUsed: []),
        .registrationRotationDeg: .init(tier: .t1, inputs: [.refRegistration], roisUsed: []),
        .registrationScale: .init(tier: .t1, inputs: [.refRegistration], roisUsed: []),
        .shoulderAngleDeg: .init(tier: .t0, inputs: [.poseLandmarks], roisUsed: []),
        .torsoLeanAngleDeg: .init(tier: .t0, inputs: [.poseLandmarks], roisUsed: []),
        .verticalConvergeDeg: .init(tier: .t1, inputs: [.frameLines], roisUsed: []),
    ]

    static var t0Count: Int {
        contracts.values.filter { $0.tier == .t0 }.count
    }

    static var t1Count: Int {
        contracts.values.filter { $0.tier == .t1 }.count
    }
}
