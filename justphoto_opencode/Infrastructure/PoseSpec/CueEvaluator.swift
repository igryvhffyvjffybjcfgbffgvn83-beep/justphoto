import Foundation

// M6.12 Phase A: Stateless cue evaluator (threshold-only, no memory/state).

enum CueLevel: String, Sendable {
    case none
    case enter
    case warn
    case hard
    case exit
}

enum CueRefMode: String, Sendable {
    case noRef
    case withRef
}

enum CueThresholdOp: String, Sendable {
    case greater = ">"
    case greaterOrEqual = ">="
    case less = "<"
    case lessOrEqual = "<="
    case absGreater = "abs>"
    case absGreaterOrEqual = "abs>="
    case absLess = "abs<"
    case absLessOrEqual = "abs<="
    case between = "between"
}

struct CueThreshold: Sendable {
    let id: String
    let op: CueThresholdOp
    let a: Double
    let b: Double?

    func matches(_ value: Double) -> Bool {
        switch op {
        case .greater:
            return value > a
        case .greaterOrEqual:
            return value >= a
        case .less:
            return value < a
        case .lessOrEqual:
            return value <= a
        case .absGreater:
            return abs(value) > a
        case .absGreaterOrEqual:
            return abs(value) >= a
        case .absLess:
            return abs(value) < a
        case .absLessOrEqual:
            return abs(value) <= a
        case .between:
            guard let b else { return false }
            let lo = min(a, b)
            let hi = max(a, b)
            return value >= lo && value <= hi
        }
    }
}

struct CueThresholdSet: Sendable {
    let enter: [CueThreshold]
    let warn: [CueThreshold]
    let hard: [CueThreshold]
    let exit: [CueThreshold]

    var evaluatedCount: Int {
        enter.count + warn.count + hard.count + exit.count
    }
}

struct CueSpec: Sendable {
    let cueId: String
    let metricKey: MetricKey?
    let withRef: CueThresholdSet?
    let noRef: CueThresholdSet?
}

struct CueEvaluationResult: Sendable {
    let cueId: String
    let level: CueLevel
    let matchedThresholdId: String?
    let evaluatedThresholdCount: Int
    let usedRefMode: CueRefMode
}

enum CueEvaluator {
    static func evaluate(
        cue: CueSpec,
        metrics: [MetricKey: MetricOutput],
        hasReference: Bool
    ) -> CueEvaluationResult {
        let value = cue.metricKey.flatMap { metrics[$0]?.value }
        return evaluate(cue: cue, metricValue: value, hasReference: hasReference)
    }

    static func evaluate(
        cue: CueSpec,
        metricValue: Double?,
        hasReference: Bool
    ) -> CueEvaluationResult {
        // Glue: choose the threshold set by hasReference; fallback to noRef when withRef is missing.
        let usedRefMode: CueRefMode = (hasReference && cue.withRef != nil) ? .withRef : .noRef
        let thresholds = (usedRefMode == .withRef) ? cue.withRef : cue.noRef
        let evaluatedCount = thresholds?.evaluatedCount ?? 0

        guard let thresholds, let value = metricValue, value.isFinite else {
            return CueEvaluationResult(
                cueId: cue.cueId,
                level: .none,
                matchedThresholdId: nil,
                evaluatedThresholdCount: evaluatedCount,
                usedRefMode: usedRefMode
            )
        }

        if let matched = firstMatch(in: thresholds.hard, value: value) {
            return result(cue: cue, level: .hard, thresholdId: matched.id, count: evaluatedCount, mode: usedRefMode)
        }
        if let matched = firstMatch(in: thresholds.warn, value: value) {
            return result(cue: cue, level: .warn, thresholdId: matched.id, count: evaluatedCount, mode: usedRefMode)
        }
        if let matched = firstMatch(in: thresholds.enter, value: value) {
            return result(cue: cue, level: .enter, thresholdId: matched.id, count: evaluatedCount, mode: usedRefMode)
        }
        if let matched = firstMatch(in: thresholds.exit, value: value) {
            return result(cue: cue, level: .exit, thresholdId: matched.id, count: evaluatedCount, mode: usedRefMode)
        }

        return result(cue: cue, level: .none, thresholdId: nil, count: evaluatedCount, mode: usedRefMode)
    }

    private static func firstMatch(in thresholds: [CueThreshold], value: Double) -> CueThreshold? {
        for t in thresholds where t.matches(value) {
            return t
        }
        return nil
    }

    private static func result(
        cue: CueSpec,
        level: CueLevel,
        thresholdId: String?,
        count: Int,
        mode: CueRefMode
    ) -> CueEvaluationResult {
        CueEvaluationResult(
            cueId: cue.cueId,
            level: level,
            matchedThresholdId: thresholdId,
            evaluatedThresholdCount: count,
            usedRefMode: mode
        )
    }
}

#if DEBUG
enum CueEvaluatorDebug {
    static func injectMetricCase(_ caseId: String) -> CueEvaluationResult? {
        guard caseId == "FRAME_MOVE_LEFT_HARD" else { return nil }
        print("InjectMetricCase: FRAME_MOVE_LEFT_HARD")

        let hard = CueThreshold(id: "hard:>0.12", op: .greater, a: 0.12, b: nil)
        let warn = CueThreshold(id: "warn:>0.07", op: .greater, a: 0.07, b: nil)
        let exit = CueThreshold(id: "exit:<=0.04", op: .lessOrEqual, a: 0.04, b: nil)
        let thresholds = CueThresholdSet(enter: [], warn: [warn], hard: [hard], exit: [exit])

        let cue = CueSpec(
            cueId: "FRAME_MOVE_LEFT",
            metricKey: .centerXOffset,
            withRef: nil,
            noRef: thresholds
        )

        let metrics: [MetricKey: MetricOutput] = [
            .centerXOffset: .available(0.15)
        ]

        return CueEvaluator.evaluate(cue: cue, metrics: metrics, hasReference: false)
    }
}
#endif
