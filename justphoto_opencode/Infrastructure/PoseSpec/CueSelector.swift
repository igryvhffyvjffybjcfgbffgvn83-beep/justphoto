import Foundation

// M6.13 Phase 2: Cue selection with priority/severity tie-breakers.

struct CueSelectionCandidate: Sendable {
    let cueId: String
    let priority: Int
    let mutexGroup: String
    let evaluation: CueEvaluationResult
    // Glue: provide raw error/hardThreshold when available; selector computes normalized severity.
    let errorValue: Double?
    // For abs/between rules, pass the max-abs threshold so severity stays comparable.
    let hardThresholdAbs: Double?
}

struct CueSelectionResult: Sendable {
    let candidate: CueSelectionCandidate
    let reason: String
}

enum CueSelector {
    private enum TieBreaker: String {
        case effectivePriorityDesc = "effectivePriority_desc"
        case severityDesc = "severity_desc"
        case priorityDesc = "priority_desc"
        case mutexGroup = "mutexGroup"
        case cueId = "id"
    }

    private struct DerivedCandidate: Sendable {
        let base: CueSelectionCandidate
        let severityNormalized: Double?
        let effectivePriority: Int
    }

    private static let tieBreakers: [TieBreaker] = [
        .effectivePriorityDesc,
        .severityDesc,
        .priorityDesc,
        .mutexGroup,
        .cueId,
    ]

    private static let severityBoosts: [(threshold: Double, add: Int)] = [
        (1.75, 2),
        (1.25, 1),
    ]

    private static let effectivePriorityCap: Int = 6

    static func pickOne(_ candidates: [CueSelectionCandidate]) -> CueSelectionResult? {
        guard !candidates.isEmpty else { return nil }

        let derived = candidates.map { derive($0) }
        let sorted = derived.sorted { a, b in
            compare(a, b)
        }

        guard let winner = sorted.first else { return nil }
        let reason = buildReason(winner: winner, all: sorted)
        return CueSelectionResult(candidate: winner.base, reason: reason)
    }

    private static func derive(_ candidate: CueSelectionCandidate) -> DerivedCandidate {
        let severityNormalized = computeSeverityNormalized(
            errorValue: candidate.errorValue,
            hardThresholdAbs: candidate.hardThresholdAbs
        )

        var effectivePriority = candidate.priority
        if let severityNormalized {
            for boost in severityBoosts where severityNormalized >= boost.threshold {
                effectivePriority = min(effectivePriority + boost.add, effectivePriorityCap)
                break
            }
        }

        return DerivedCandidate(
            base: candidate,
            severityNormalized: severityNormalized,
            effectivePriority: effectivePriority
        )
    }

    private static func computeSeverityNormalized(errorValue: Double?, hardThresholdAbs: Double?) -> Double? {
        guard let errorValue, let hardThresholdAbs, hardThresholdAbs > 0 else { return nil }
        let value = abs(errorValue) / hardThresholdAbs
        return value.isFinite ? value : nil
    }

    private static func compare(_ a: DerivedCandidate, _ b: DerivedCandidate) -> Bool {
        for rule in tieBreakers {
            switch rule {
            case .effectivePriorityDesc:
                if a.effectivePriority != b.effectivePriority {
                    return a.effectivePriority > b.effectivePriority
                }
            case .severityDesc:
                let av = a.severityNormalized ?? -Double.greatestFiniteMagnitude
                let bv = b.severityNormalized ?? -Double.greatestFiniteMagnitude
                if av != bv {
                    return av > bv
                }
            case .priorityDesc:
                if a.base.priority != b.base.priority {
                    return a.base.priority > b.base.priority
                }
            case .mutexGroup:
                if a.base.mutexGroup != b.base.mutexGroup {
                    return a.base.mutexGroup < b.base.mutexGroup
                }
            case .cueId:
                if a.base.cueId != b.base.cueId {
                    return a.base.cueId < b.base.cueId
                }
            }
        }
        return false
    }

    private static func buildReason(winner: DerivedCandidate, all: [DerivedCandidate]) -> String {
        let sev = winner.severityNormalized.map { String(format: "%.2f", $0) } ?? "nil"
        let tail = all.dropFirst().prefix(2).map { $0.base.cueId }.joined(separator: ",")
        return "tieBreakers=\(tieBreakers.map { $0.rawValue }.joined(separator: ",")) " +
            "effectivePriority=\(winner.effectivePriority) severity=\(sev) priority=\(winner.base.priority) " +
            "mutexGroup=\(winner.base.mutexGroup) tail=\(tail)"
    }
}

#if DEBUG
enum CueSelectorDebug {
    static func validateSingleCandidate() -> CueSelectionResult? {
        guard let eval = CueEvaluatorDebug.injectMetricCase("FRAME_MOVE_LEFT_HARD") else { return nil }
        let candidate = CueSelectionCandidate(
            cueId: eval.cueId,
            priority: 4,
            mutexGroup: "FRAME_X",
            evaluation: eval,
            errorValue: 0.15,
            hardThresholdAbs: 0.12
        )
        return CueSelector.pickOne([candidate])
    }

    static func validateEmpty() -> CueSelectionResult? {
        CueSelector.pickOne([])
    }

    static func validatePriorityWins() -> CueSelectionResult? {
        let eval = CueEvaluationResult(
            cueId: "PRIORITY_HIGH",
            level: .hard,
            matchedThresholdId: "hard:>0.10",
            evaluatedThresholdCount: 1,
            usedRefMode: .noRef
        )
        let high = CueSelectionCandidate(
            cueId: "PRIORITY_HIGH",
            priority: 5,
            mutexGroup: "FRAME_X",
            evaluation: eval,
            errorValue: 0.05,
            hardThresholdAbs: 0.1
        )
        let low = CueSelectionCandidate(
            cueId: "PRIORITY_LOW",
            priority: 3,
            mutexGroup: "FRAME_Y",
            evaluation: eval,
            errorValue: 0.1,
            hardThresholdAbs: 0.1
        )
        return CueSelector.pickOne([low, high])
    }

    static func validateSeverityBoostWins() -> CueSelectionResult? {
        let eval = CueEvaluationResult(
            cueId: "SEVERITY_HIGH",
            level: .hard,
            matchedThresholdId: "hard:>0.10",
            evaluatedThresholdCount: 1,
            usedRefMode: .noRef
        )
        let mild = CueSelectionCandidate(
            cueId: "SEVERITY_MILD",
            priority: 4,
            mutexGroup: "DIST",
            evaluation: eval,
            errorValue: 0.05,
            hardThresholdAbs: 0.1
        )
        let severe = CueSelectionCandidate(
            cueId: "SEVERITY_HIGH",
            priority: 3,
            mutexGroup: "DIST",
            evaluation: eval,
            errorValue: 0.2,
            hardThresholdAbs: 0.1
        )
        return CueSelector.pickOne([mild, severe])
    }
}
#endif
