import Foundation

// PRD Milestone 4A (M4.2): SessionRuleGate is the single source of truth for
// whether shutter should be enabled.
//
// Gates (PRD-aligned):
// - camera permission must be authorized
// - warmup must be ready
// - global write_failed block
// - in-flight <= 2
// - workset < 20
enum SessionRuleGate {
    static let maxWorksetCount: Int = 20
    static let maxInFlightCount: Int = 2

    enum ShutterDisabledReason: String, Sendable, Equatable {
        case camera_not_authorized
        case warmup_not_ready
        case warmup_failed
        case blocked_by_write_failed
        case in_flight_limit_reached
        case workset_full
    }

    struct Inputs: Sendable, Equatable {
        let cameraAuth: CameraAuth
        let warmupPhase: WarmupPhase
        let worksetCount: Int
        let inFlightCount: Int
        let writeFailedCount: Int

        init(
            cameraAuth: CameraAuth,
            warmupPhase: WarmupPhase,
            worksetCount: Int,
            inFlightCount: Int,
            writeFailedCount: Int
        ) {
            self.cameraAuth = cameraAuth
            self.warmupPhase = warmupPhase
            self.worksetCount = max(0, worksetCount)
            self.inFlightCount = max(0, inFlightCount)
            self.writeFailedCount = max(0, writeFailedCount)
        }
    }

    struct Result: Sendable, Equatable {
        let isEnabled: Bool
        let reason: ShutterDisabledReason?
        let debugDescription: String
    }

    static func evaluate(_ inputs: Inputs) -> Result {
        // Deterministic priority (one clear reason):
        // 1) permission
        // 2) warmup
        // 3) write_failed (data safety)
        // 4) in-flight
        // 5) workset full
        if inputs.cameraAuth != .authorized {
            return Result(
                isEnabled: false,
                reason: .camera_not_authorized,
                debugDescription: "disabled:camera_not_authorized auth=\(inputs.cameraAuth.rawValue)"
            )
        }

        if inputs.warmupPhase == .failed {
            return Result(
                isEnabled: false,
                reason: .warmup_failed,
                debugDescription: "disabled:warmup_failed phase=failed"
            )
        }

        if inputs.warmupPhase != .ready {
            return Result(
                isEnabled: false,
                reason: .warmup_not_ready,
                debugDescription: "disabled:warmup_not_ready phase=\(inputs.warmupPhase.rawValue)"
            )
        }

        if inputs.writeFailedCount > 0 {
            return Result(
                isEnabled: false,
                reason: .blocked_by_write_failed,
                debugDescription: "disabled:blocked_by_write_failed write_failed=\(inputs.writeFailedCount)"
            )
        }

        if inputs.inFlightCount >= maxInFlightCount {
            return Result(
                isEnabled: false,
                reason: .in_flight_limit_reached,
                debugDescription: "disabled:in_flight_limit_reached in_flight=\(inputs.inFlightCount) max=\(maxInFlightCount)"
            )
        }

        if inputs.worksetCount >= maxWorksetCount {
            return Result(
                isEnabled: false,
                reason: .workset_full,
                debugDescription: "disabled:workset_full workset=\(inputs.worksetCount) max=\(maxWorksetCount)"
            )
        }

        return Result(
            isEnabled: true,
            reason: nil,
            debugDescription: "enabled"
        )
    }
}
