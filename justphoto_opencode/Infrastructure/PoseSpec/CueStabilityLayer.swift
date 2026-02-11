import Foundation

// M6.12 Phase B: Lightweight cue stability layer (frame-count only, no time).

enum CueStabilityState: String, Sendable {
    case unstable
    case confirmed
}

struct CueStabilityResult: Sendable {
    let cueId: String
    let level: CueLevel
    let matchedThresholdId: String?
    let evaluatedThresholdCount: Int
    let usedRefMode: CueRefMode
    let stableFrameCount: Int
    let stabilityState: CueStabilityState
}

final class CueStabilityLayer {
    private let hardStableFrames = 2
    private let exitStableFrames = 2

    private var previousCueId: String? = nil
    private var previousLevel: CueLevel = .none
    private var stableFrameCount: Int = 0

    func reset() {
        previousCueId = nil
        previousLevel = .none
        stableFrameCount = 0
    }

    func apply(_ evaluation: CueEvaluationResult) -> CueStabilityResult {
        // Glue: only apply stability to hard/exit; warn/enter pass through immediately.
        let prevCueId = previousCueId
        let prevLevel = previousLevel

        let sameAsPrev = (evaluation.cueId == prevCueId && evaluation.level == prevLevel)
        if prevCueId == nil {
            stableFrameCount = 0
        } else if sameAsPrev {
            stableFrameCount += 1
        } else {
            stableFrameCount = 0
        }

        var outputCueId = evaluation.cueId
        var outputLevel = evaluation.level
        var outputThresholdId = evaluation.matchedThresholdId
        var stabilityState: CueStabilityState = .confirmed

        switch evaluation.level {
        case .hard:
            let confirmed = sameAsPrev && stableFrameCount >= (hardStableFrames - 1)
            if !confirmed {
                outputCueId = prevCueId ?? evaluation.cueId
                outputLevel = prevLevel
                outputThresholdId = nil
                stabilityState = .unstable
            }
        case .exit:
            let confirmed = sameAsPrev && stableFrameCount >= (exitStableFrames - 1)
            if !confirmed {
                outputCueId = prevCueId ?? evaluation.cueId
                outputLevel = prevLevel
                outputThresholdId = nil
                stabilityState = .unstable
            }
        case .warn, .enter, .none:
            break
        }

        // Rule 4: cue change resets the stability counter.
        if evaluation.cueId != prevCueId {
            stableFrameCount = 0
        }

        previousCueId = evaluation.cueId
        previousLevel = evaluation.level

        let result = CueStabilityResult(
            cueId: outputCueId,
            level: outputLevel,
            matchedThresholdId: outputThresholdId,
            evaluatedThresholdCount: evaluation.evaluatedThresholdCount,
            usedRefMode: evaluation.usedRefMode,
            stableFrameCount: stableFrameCount,
            stabilityState: stabilityState
        )
        #if DEBUG
        print("CueStability: stableFrameCount=\(result.stableFrameCount) stabilityState=\(result.stabilityState.rawValue)")
        #endif
        return result
    }
}
