import Foundation

// Session-scoped in-memory storage for withRef target outputs (numbers only).
final class RefTargetSessionStore {
    static let shared = RefTargetSessionStore()

    struct Snapshot: Sendable {
        let sessionId: String
        let targets: [MetricKey: Double]
        let updatedAt: Date
    }

    private let queue = DispatchQueue(label: "RefTargetSessionStore.queue")
    private var snapshotsBySession: [String: Snapshot] = [:]

    private init() {}

    func setTargetsForCurrentSession(metrics: [MetricKey: MetricOutput]) -> Snapshot? {
        guard let sessionId = (try? SessionRepository.shared.currentSessionId()) ?? nil else {
            return nil
        }

        let values = Self.extractTargets(from: metrics)
        let newCount = values.count

        return queue.sync {
            let existing = snapshotsBySession[sessionId]
            let existingCount = existing?.targets.count ?? 0

            if existing != nil {
                if newCount == 0 {
                    JPDebugPrint("RefTargetStoreSkipped: empty_targets_keep_existing session_id=\(sessionId) existing=\(existingCount)")
                    return existing
                }
                if newCount < 5 {
                    JPDebugPrint("RefTargetStoreSkipped: low_metrics_keep_existing session_id=\(sessionId) new=\(newCount) existing=\(existingCount)")
                    return existing
                }
                if newCount < existingCount {
                    JPDebugPrint("RefTargetStoreSkipped: downgrade_keep_existing session_id=\(sessionId) new=\(newCount) existing=\(existingCount)")
                    return existing
                }
            } else if newCount == 0 {
                JPDebugPrint("RefTargetStoreSkipped: empty_targets session_id=\(sessionId)")
                return nil
            }

            let snapshot = Snapshot(sessionId: sessionId, targets: values, updatedAt: Date())
            snapshotsBySession[sessionId] = snapshot
            JPDebugPrint("RefTargetStoreSet: session_id=\(sessionId) metrics=\(newCount)")
            return snapshot
        }
    }

    func currentSnapshot() -> Snapshot? {
        guard let sessionId = (try? SessionRepository.shared.currentSessionId()) ?? nil else {
            return nil
        }
        return queue.sync {
            snapshotsBySession[sessionId]
        }
    }

    func clear(sessionId: String) {
        queue.sync {
            _ = snapshotsBySession.removeValue(forKey: sessionId)
        }
        JPDebugPrint("RefTargetStoreCleared: session_id=\(sessionId)")
    }

    private static func extractTargets(from metrics: [MetricKey: MetricOutput]) -> [MetricKey: Double] {
        var out: [MetricKey: Double] = [:]
        for (key, output) in metrics {
            guard let value = output.value, value.isFinite else { continue }
            out[key] = value
        }
        return out
    }
}
