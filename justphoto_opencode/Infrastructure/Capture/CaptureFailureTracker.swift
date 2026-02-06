import Foundation

// M4.19: Rolling window tracker for capture_failed.
// Trigger: 3 failures within 30 seconds -> show L3 "相机异常".
actor CaptureFailureTracker {
    static let shared = CaptureFailureTracker()

    private let windowMs: Int64 = 30_000
    private let triggerCount: Int = 3

    private var failureAtMs: [Int64] = []

    private init() {}

    struct RecordResult: Sendable, Equatable {
        let countInWindow: Int
        let didTrigger: Bool
    }

    func recordFailure(now: Date = .init()) -> RecordResult {
        let nowMs = Int64(now.timeIntervalSince1970 * 1000)
        failureAtMs.append(nowMs)
        prune(nowMs: nowMs)

        let count = failureAtMs.count
        return RecordResult(
            countInWindow: count,
            didTrigger: count >= triggerCount
        )
    }

    func currentCount(now: Date = .init()) -> Int {
        let nowMs = Int64(now.timeIntervalSince1970 * 1000)
        prune(nowMs: nowMs)
        return failureAtMs.count
    }

    func reset() {
        failureAtMs.removeAll(keepingCapacity: true)
    }

    private func prune(nowMs: Int64) {
        let cutoff = nowMs - windowMs
        if failureAtMs.isEmpty { return }
        failureAtMs.removeAll { $0 < cutoff }
    }
}
