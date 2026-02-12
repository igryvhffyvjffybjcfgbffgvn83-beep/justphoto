import Foundation

// M6.14 Phase 1: Anti-jitter state machine (pure logic, no external dependencies).

struct AntiJitterInput: Sendable {
    let cueId: String
    let level: CueLevel
}

final class AntiJitterGate {
    private let persistFrames: Int
    private let minHoldMs: Int
    private let cooldownMs: Int

    // State fields (explicitly tracked for deterministic behavior).
    private(set) var currentCueId: String? = nil
    private(set) var currentLevel: CueLevel = .none
    private(set) var stableFrameCount: Int = 0
    private(set) var candidateCueId: String? = nil
    private(set) var candidateSinceMs: Int = 0
    private(set) var lastOutputChangeMs: Int = 0
    private(set) var cooldownUntilByCueId: [String: Int] = [:]
    private(set) var lastInputCueId: String? = nil
    private(set) var lastInputLevel: CueLevel = .none

    init(persistFrames: Int, minHoldMs: Int, cooldownMs: Int) {
        self.persistFrames = max(1, persistFrames)
        self.minHoldMs = max(0, minHoldMs)
        self.cooldownMs = max(0, cooldownMs)
    }

    func reset() {
        currentCueId = nil
        currentLevel = .none
        stableFrameCount = 0
        candidateCueId = nil
        candidateSinceMs = 0
        lastOutputChangeMs = 0
        cooldownUntilByCueId = [:]
        lastInputCueId = nil
        lastInputLevel = .none
    }

    func filter(inputCue: AntiJitterInput?, timestampMs: Int) -> AntiJitterInput? {
        filterWithReason(inputCue: inputCue, timestampMs: timestampMs).output
    }

    func filterWithReason(
        inputCue: AntiJitterInput?,
        timestampMs: Int
    ) -> (output: AntiJitterInput?, reason: String) {
        let inputCueId = inputCue?.cueId
        let inputLevel = inputCue?.level ?? .none

        let sameAsLastInput = (inputCueId == lastInputCueId && inputLevel == lastInputLevel)
        if sameAsLastInput {
            stableFrameCount += 1
        } else {
            stableFrameCount = 1
            candidateSinceMs = timestampMs
        }
        lastInputCueId = inputCueId
        lastInputLevel = inputLevel
        candidateCueId = inputCueId

        if inputCueId == currentCueId && inputLevel == currentLevel {
            return (currentOutput(), "none")
        }

        let holdSatisfied = (currentCueId == nil) || (timestampMs - lastOutputChangeMs >= minHoldMs)
        if !holdSatisfied {
            return (currentOutput(), "hold")
        }

        if inputCueId == nil {
            guard stableFrameCount >= persistFrames else { return (currentOutput(), "frames") }
            return (switchOutput(to: nil, timestampMs: timestampMs), "none")
        }

        if let until = cooldownUntilByCueId[inputCueId ?? ""], until > timestampMs, currentCueId != inputCueId {
            return (currentOutput(), "cooldown")
        }

        guard stableFrameCount >= persistFrames else { return (currentOutput(), "frames") }
        return (switchOutput(to: inputCue, timestampMs: timestampMs), "none")
    }

    private func currentOutput() -> AntiJitterInput? {
        guard let id = currentCueId else { return nil }
        return AntiJitterInput(cueId: id, level: currentLevel)
    }

    private func switchOutput(to input: AntiJitterInput?, timestampMs: Int) -> AntiJitterInput? {
        let previousCueId = currentCueId

        currentCueId = input?.cueId
        currentLevel = input?.level ?? .none

        if let prev = previousCueId, prev != currentCueId {
            cooldownUntilByCueId[prev] = timestampMs + cooldownMs
        }

        lastOutputChangeMs = timestampMs
        return input
    }
}

#if DEBUG
enum AntiJitterGateDebug {
    static func simulateHoldVsFrames() -> [String] {
        let gate = AntiJitterGate(persistFrames: 3, minHoldMs: 3000, cooldownMs: 800)
        let a = AntiJitterInput(cueId: "A", level: .hard)
        let b = AntiJitterInput(cueId: "B", level: .hard)

        let frames: [(t: Int, input: AntiJitterInput?)] = [
            (0, a),
            (100, a),
            (200, a),
            (300, a),
            // Candidate B arrives but minHoldMs not met; output should stay A.
            (800, b),
            (900, b),
            (1000, b),
            // After minHoldMs, B can take over once stable.
            (3200, b),
            (3300, b),
            (3400, b),
            (3500, b),
        ]

        var out: [String] = []
        for f in frames {
            let result = gate.filter(inputCue: f.input, timestampMs: f.t)
            let inStr = f.input?.cueId ?? "<nil>"
            let outStr = result?.cueId ?? "<nil>"
            out.append("t=\(f.t) in=\(inStr) out=\(outStr)")
        }
        return out
    }
}
#endif
