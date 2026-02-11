import Foundation
import Combine

// PRD 4.1.1/4.1.2: camera warmup overlay + timeouts.

enum WarmupPhase: String, Codable, Sendable {
    case idle
    case warming
    case upgraded
    case ready
    case failed
}

enum WarmupDebugSettings {
    static let simulateReadyDelaySecKey = "debug_simulate_warmup_ready_delay_sec"

    static func simulatedReadyDelaySec() -> Double {
        // Default: no artificial delay.
        let v = UserDefaults.standard.double(forKey: simulateReadyDelaySecKey)
        return max(0.0, v)
    }

    static func setSimulatedReadyDelaySec(_ seconds: Double?) {
        if let seconds {
            UserDefaults.standard.set(seconds, forKey: simulateReadyDelaySecKey)
        } else {
            UserDefaults.standard.removeObject(forKey: simulateReadyDelaySecKey)
        }
    }
}

@MainActor
final class WarmupTracker: ObservableObject {
    @Published private(set) var phase: WarmupPhase = .idle

    private var upgradeTask: Task<Void, Never>?
    private var failTask: Task<Void, Never>?
    private var readyTask: Task<Void, Never>?

#if DEBUG
    private static var debugProbeTracker: WarmupTracker?
#endif

    func startIfNeeded(simulatedReadyDelaySec: Double) {
        switch phase {
        case .idle, .ready:
            start(simulatedReadyDelaySec: simulatedReadyDelaySec)
        case .warming, .upgraded, .failed:
            break
        }
    }

    func start(simulatedReadyDelaySec: Double) {
        cancelTasks()
        phase = .warming

        // PRD: upgrade message at 3s.
        upgradeTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 3_000_000_000)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self else { return }
                guard self.phase == .warming else { return }
                self.phase = .upgraded
            }
        }

        // PRD: hard fail at 8s.
        failTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 8_000_000_000)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self else { return }
                guard self.phase != .ready else { return }
                self.phase = .failed
            }
        }

        // Simulated ready (until real camera pipeline exists).
        if simulatedReadyDelaySec <= 0 {
            phase = .ready
            cancelTasks()
            return
        }

        let ns = UInt64(min(120.0, simulatedReadyDelaySec) * 1_000_000_000)
        readyTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: ns)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self else { return }
                guard self.phase != .failed else { return }
                self.phase = .ready
                self.cancelTasks()
            }
        }
    }

    func stop() {
        cancelTasks()
        phase = .idle
    }

    private func cancelTasks() {
        upgradeTask?.cancel()
        failTask?.cancel()
        readyTask?.cancel()
        upgradeTask = nil
        failTask = nil
        readyTask = nil
    }

#if DEBUG
    static func debugStartCancelProbe() {
        let tracker = WarmupTracker()
        debugProbeTracker = tracker

        print("WarmupCancelProbe: start")
        tracker.start(simulatedReadyDelaySec: 5.0)

        Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: 200_000_000)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            tracker.stop()
            print("WarmupCancelProbe: stop")
        }

        Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: 4_000_000_000)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            print("WarmupCancelProbe: phase_after_4s=\(tracker.phase.rawValue)")
        }

        Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: 9_000_000_000)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            print("WarmupCancelProbe: phase_after_9s=\(tracker.phase.rawValue)")
        }
    }
#endif
}
