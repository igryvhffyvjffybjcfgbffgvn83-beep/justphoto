import Foundation

// M6.19: MatchDecider = PoseSpec withRef exit equivalence (no hard-coded thresholds).

struct MatchDeciderResult: Sendable {
    let match: Bool
    let requiredDimensions: [String]
    let blockedBy: [String]
    let mirrorApplied: Bool
    let stableExitFramesByCueId: [String: Int]
}

enum MatchExitValueSource: Sendable {
    case errorValue
    case rawMetricWhenBetweenExit
}

struct MatchCueDefinition: Sendable {
    let cueId: String
    let metricKey: MetricKey
    let cueSpec: CueSpec
    let persistFrames: Int
    let dimensionKey: String
    let exitValueSource: MatchExitValueSource
}

enum MatchDeciderError: Error {
    case invalidPoseSpec
}

final class MatchDecider {
    private struct CueCheckState {
        let cue: MatchCueDefinition
        let level: CueLevel
        let missingData: Bool
        let isExit: Bool
        let persistSatisfied: Bool
        let stableFrames: Int
        let errorMagnitude: Double?
    }

    private let cues: [MatchCueDefinition]
    private var stableExitFramesByCueId: [String: Int] = [:]

    init(cues: [MatchCueDefinition]) {
        self.cues = cues
    }

    func debugRequiredCueIds() -> [String] {
        cues.map(\.cueId)
    }

    func reset() {
        stableExitFramesByCueId = [:]
    }

    func evaluate(
        metrics: [MetricKey: MetricOutput],
        targets: [MetricKey: Double]
    ) -> MatchDeciderResult {
        let requiredDimensions = cues.map { $0.cueId }
        let mirroredMetrics = MirrorEvaluator.mirrorMetricOutputs(metrics)

        var states: [CueCheckState] = []
        states.reserveCapacity(cues.count)

        var mirrorApplied = false

        for cue in cues {
            let cueId = cue.cueId
            let persistFrames = max(1, cue.persistFrames)

            guard let target = targets[cue.metricKey] else {
                stableExitFramesByCueId[cueId] = 0
                states.append(
                    CueCheckState(
                        cue: cue,
                        level: .none,
                        missingData: true,
                        isExit: false,
                        persistSatisfied: false,
                        stableFrames: 0,
                        errorMagnitude: nil
                    )
                )
                continue
            }

            guard let output = metrics[cue.metricKey], let rawValue = output.value else {
                stableExitFramesByCueId[cueId] = 0
                states.append(
                    CueCheckState(
                        cue: cue,
                        level: .none,
                        missingData: true,
                        isExit: false,
                        persistSatisfied: false,
                        stableFrames: 0,
                        errorMagnitude: nil
                    )
                )
                continue
            }

            if output.reason != nil || !rawValue.isFinite {
                stableExitFramesByCueId[cueId] = 0
                states.append(
                    CueCheckState(
                        cue: cue,
                        level: .none,
                        missingData: true,
                        isExit: false,
                        persistSatisfied: false,
                        stableFrames: 0,
                        errorMagnitude: nil
                    )
                )
                continue
            }

            guard let eval = WithRefErrorEvaluator.evaluate(
                metricKey: cue.metricKey,
                currentMetrics: metrics,
                mirroredMetrics: mirroredMetrics,
                target: target
            ), let errorValue = eval.errorValue else {
                stableExitFramesByCueId[cueId] = 0
                states.append(
                    CueCheckState(
                        cue: cue,
                        level: .none,
                        missingData: true,
                        isExit: false,
                        persistSatisfied: false,
                        stableFrames: 0,
                        errorMagnitude: nil
                    )
                )
                continue
            }

            mirrorApplied = mirrorApplied || eval.mirrorApplied

            let errorEval = CueEvaluator.evaluate(
                cue: cue.cueSpec,
                metricValue: errorValue,
                hasReference: true
            )

            let rawBetweenExitSatisfied: Bool = {
                guard cue.exitValueSource == .rawMetricWhenBetweenExit else { return false }
                return evaluateExitOnly(cue: cue.cueSpec, metricValue: rawValue)
            }()

            let isExit = (errorEval.level == .exit) || rawBetweenExitSatisfied
            let resolvedLevel: CueLevel = isExit ? .exit : errorEval.level

            let stableFrames: Int = {
                if isExit {
                    let prev = stableExitFramesByCueId[cueId] ?? 0
                    let next = prev + 1
                    stableExitFramesByCueId[cueId] = next
                    return next
                }
                stableExitFramesByCueId[cueId] = 0
                return 0
            }()

            states.append(
                CueCheckState(
                    cue: cue,
                    level: resolvedLevel,
                    missingData: false,
                    isExit: isExit,
                    persistSatisfied: isExit && stableFrames >= persistFrames,
                    stableFrames: stableFrames,
                    errorMagnitude: abs(errorValue)
                )
            )
        }

        let blockedBy = blockedCueIds(states: states)
        let match = !requiredDimensions.isEmpty && blockedBy.isEmpty

        return MatchDeciderResult(
            match: match,
            requiredDimensions: requiredDimensions,
            blockedBy: blockedBy,
            mirrorApplied: mirrorApplied,
            stableExitFramesByCueId: stableExitFramesByCueId
        )
    }

    private func blockedCueIds(states: [CueCheckState]) -> [String] {
        let grouped = Dictionary(grouping: states, by: { $0.cue.dimensionKey })
        let orderedKeys = grouped.keys.sorted()

        var out: [String] = []
        out.reserveCapacity(grouped.count)

        for key in orderedKeys {
            guard let items = grouped[key] else { continue }

            if let missing = items.filter(\.missingData).sorted(by: cueStateOrder).first {
                out.append(missing.cue.cueId)
                continue
            }

            let nonExit = items.filter { !$0.isExit }
            if let blocker = nonExit.sorted(by: nonExitOrder).first {
                out.append(blocker.cue.cueId)
                continue
            }

            let notPersisted = items.filter { $0.isExit && !$0.persistSatisfied }
            if let blocker = notPersisted.sorted(by: persistOrder).first {
                out.append(blocker.cue.cueId)
                continue
            }
        }

        return out
    }

    private func evaluateExitOnly(cue: CueSpec, metricValue: Double) -> Bool {
        guard let withRef = cue.withRef else { return false }
        let exitOnlySpec = CueSpec(
            cueId: cue.cueId,
            metricKey: cue.metricKey,
            withRef: CueThresholdSet(
                enter: [],
                warn: [],
                hard: [],
                exit: withRef.exit
            ),
            noRef: nil
        )
        let exitEval = CueEvaluator.evaluate(
            cue: exitOnlySpec,
            metricValue: metricValue,
            hasReference: true
        )
        return exitEval.level == .exit
    }

    private func levelRank(_ level: CueLevel) -> Int {
        switch level {
        case .hard:
            return 4
        case .warn:
            return 3
        case .enter:
            return 2
        case .none:
            return 1
        case .exit:
            return 0
        }
    }

    private func nonExitOrder(_ lhs: CueCheckState, _ rhs: CueCheckState) -> Bool {
        let lRank = levelRank(lhs.level)
        let rRank = levelRank(rhs.level)
        if lRank != rRank {
            return lRank > rRank
        }
        let lErr = lhs.errorMagnitude ?? -Double.infinity
        let rErr = rhs.errorMagnitude ?? -Double.infinity
        if lErr != rErr {
            return lErr > rErr
        }
        return cueStateOrder(lhs, rhs)
    }

    private func persistOrder(_ lhs: CueCheckState, _ rhs: CueCheckState) -> Bool {
        if lhs.stableFrames != rhs.stableFrames {
            return lhs.stableFrames < rhs.stableFrames
        }
        return cueStateOrder(lhs, rhs)
    }

    private func cueStateOrder(_ lhs: CueCheckState, _ rhs: CueCheckState) -> Bool {
        lhs.cue.cueId < rhs.cue.cueId
    }
}

enum MatchDeciderBuilder {
    private static let strongMatchMetrics: Set<MetricKey> = [
        .centerXOffset,
        .centerYOffset,
        .headroom,
        .bottomMargin,
        .bboxHeight,
        .shoulderAngleDeg,
        .hipAngleDeg,
        .torsoLeanAngleDeg,
        .eyeLineAngleDeg,
        .noseToChinRatio,
    ]

    static func buildForScene(scene: String, spec: PoseSpec) -> MatchDecider {
        let defaultsPersistFrames = spec.defaults.antiJitter.persistFrames
        let cues = parseCues(from: spec, scene: scene, defaultPersistFrames: defaultsPersistFrames)
        return MatchDecider(cues: cues)
    }

    static func cacheFingerprint(for spec: PoseSpec) -> String {
        let latest = spec.changeLog.last
        let latestMarker: String
        if let version = latest?.version {
            latestMarker = version
        } else if let date = latest?.date {
            latestMarker = date
        } else if let note = latest?.notes?.last {
            latestMarker = note
        } else if let change = latest?.changes?.last {
            latestMarker = change
        } else if let item = latest?.items?.last {
            latestMarker = item
        } else if let scope = latest?.scope {
            latestMarker = scope
        } else {
            latestMarker = "no_change_log"
        }
        return "\(spec.prdVersion)|\(latestMarker)|cues=\(spec.cues.count)"
    }

    private static func parseCues(from spec: PoseSpec, scene: String, defaultPersistFrames: Int) -> [MatchCueDefinition] {
        var out: [MatchCueDefinition] = []
        out.reserveCapacity(spec.cues.count)

        for entry in spec.cues {
            guard case .object(let obj) = entry else { continue }
            guard let cueId = string(obj["id"]),
                  let cueScene = string(obj["scene"]) else { continue }
            guard cueScene == scene || cueScene == "base" else { continue }

            guard case .object(let trigger) = obj["trigger"],
                  case .object(let withRef) = trigger["withRef"] else { continue }

            guard let errorExpr = string(withRef["error"]),
                  let metricKey = metricKeyFromError(errorExpr),
                  strongMatchMetrics.contains(metricKey) else { continue }

            let thresholds = parseThresholdSet(withRef)
            let cueSpec = CueSpec(
                cueId: cueId,
                metricKey: metricKey,
                withRef: thresholds,
                noRef: nil
            )

            let persistFrames = parsePersistFrames(obj["antiJitter"]) ?? defaultPersistFrames
            let mutexGroup = string(obj["mutexGroup"])
            let dimensionKey = {
                if let mutexGroup, !mutexGroup.isEmpty {
                    return "mutex:\(mutexGroup)"
                }
                return "metric:\(metricKey.rawValue)"
            }()

            let exitValueSource: MatchExitValueSource = hasBetweenExit(withRef)
                ? .rawMetricWhenBetweenExit
                : .errorValue

            let def = MatchCueDefinition(
                cueId: cueId,
                metricKey: metricKey,
                cueSpec: cueSpec,
                persistFrames: persistFrames,
                dimensionKey: dimensionKey,
                exitValueSource: exitValueSource
            )
            out.append(def)
        }

        return out
    }

    private static func hasBetweenExit(_ withRef: [String: JSONValue]) -> Bool {
        guard case .object(let exitObj) = withRef["exit"] else { return false }
        return exitObj["between"] != nil
    }

    private static func parseThresholdSet(_ withRef: [String: JSONValue]) -> CueThresholdSet {
        let enter = parseThresholds(withRef["enter"], prefix: "enter")
        let warn = parseThresholds(withRef["warn"], prefix: "warn")
        let hard = parseThresholds(withRef["hard"], prefix: "hard")
        let exit = parseThresholds(withRef["exit"], prefix: "exit")
        return CueThresholdSet(enter: enter, warn: warn, hard: hard, exit: exit)
    }

    private static func parseThresholds(_ value: JSONValue?, prefix: String) -> [CueThreshold] {
        guard case .object(let obj) = value else { return [] }
        var out: [CueThreshold] = []
        out.reserveCapacity(obj.count)

        for (opStr, raw) in obj {
            guard let op = CueThresholdOp(rawValue: opStr) else { continue }
            switch raw {
            case .number(let n):
                out.append(CueThreshold(id: "\(prefix):\(opStr)\(n)", op: op, a: n, b: nil))
            case .array(let arr):
                if op == .between, arr.count >= 2,
                   case .number(let a) = arr[0],
                   case .number(let b) = arr[1] {
                    out.append(CueThreshold(id: "\(prefix):\(opStr)\(a),\(b)", op: op, a: a, b: b))
                }
            default:
                continue
            }
        }
        return out
    }

    private static func parsePersistFrames(_ value: JSONValue?) -> Int? {
        guard case .object(let obj) = value else { return nil }
        guard case .number(let n) = obj["persistFrames"] else { return nil }
        return max(1, Int(n))
    }

    private static func metricKeyFromError(_ expr: String) -> MetricKey? {
        let normalized = expr.replacingOccurrences(of: " ", with: "")
        let marker = "-target."
        guard let range = normalized.range(of: marker) else { return nil }
        let left = String(normalized[..<range.lowerBound])
        let right = String(normalized[range.upperBound...])
        guard left == right else { return nil }
        return MetricKey(rawValue: left)
    }

    private static func string(_ value: JSONValue?) -> String? {
        if case .string(let s) = value { return s }
        return nil
    }
}
