import Foundation
import Combine

@MainActor
protocol PraiseControlling: ObservableObject {
    var latestSignal: PraiseSignal? { get }
    func handleExitCrossed(mutexGroup: String)
    func triggerPraise(message: String)
    func clearPraise()
}

struct PraiseSignal: Equatable {
    let id: UUID
    let message: String
    let triggeredAt: Date
}

@MainActor
final class PraiseController: PraiseControlling {
    @Published private(set) var latestSignal: PraiseSignal? = nil

    private struct Policy {
        let enabled: Bool
        let cooldownMs: Int
        let messageZh: String
    }

    private let policy: Policy
    private var lastTriggerByMutexGroup: [String: Int] = [:]

    init() {
        self.policy = Self.loadPolicy()
    }

    func handleExitCrossed(mutexGroup: String) {
        guard policy.enabled else { return }
        let nowMs = Int(Date().timeIntervalSince1970 * 1000)
        if let last = lastTriggerByMutexGroup[mutexGroup], nowMs - last < policy.cooldownMs {
            return
        }
        lastTriggerByMutexGroup[mutexGroup] = nowMs
        triggerPraise(message: policy.messageZh)
    }

    func triggerPraise(message: String = "就现在！按快门") {
        latestSignal = PraiseSignal(id: UUID(), message: message, triggeredAt: Date())
        #if DEBUG
        if let signal = latestSignal {
            print("Praise: trigger id=\(signal.id.uuidString)")
        }
        #endif
    }

    func clearPraise() {
        guard latestSignal != nil else { return }
        latestSignal = nil
        #if DEBUG
        print("Praise: clear")
        #endif
    }

    #if DEBUG
    func debugTriggerExitCrossed(mutexGroup: String = "FRAME_X") {
        handleExitCrossed(mutexGroup: mutexGroup)
        print("Praise: debug_exit_crossed mutex=\(mutexGroup)")
    }
    #endif

    private static func loadPolicy() -> Policy {
        let fallback = Policy(enabled: true, cooldownMs: 10_000, messageZh: "就现在！按快门")
        guard let spec = try? PoseSpecLoader.shared.loadPoseSpec() else { return fallback }
        guard case let .object(obj) = spec.praisePolicy else { return fallback }

        let enabled = obj["enabled"].flatMap { $0.boolValue } ?? fallback.enabled
        let cooldownMs = obj["cooldownMs"].flatMap { $0.intValue } ?? fallback.cooldownMs
        let messageZh = obj["freezeAfterExit"]
            .flatMap { $0.objectValue?["script"] }
            .flatMap { $0.objectValue?["zh"] }
            .flatMap { $0.arrayValue?.first?.stringValue } ?? fallback.messageZh

        return Policy(enabled: enabled, cooldownMs: cooldownMs, messageZh: messageZh)
    }
}

@MainActor
final class MockPraiseController: PraiseControlling {
    @Published private(set) var latestSignal: PraiseSignal? = nil

    func handleExitCrossed(mutexGroup: String) {
        triggerPraise(message: "就现在！按快门")
    }

    func triggerPraise(message: String = "就现在！按快门") {
        latestSignal = PraiseSignal(id: UUID(), message: message, triggeredAt: Date())
        #if DEBUG
        if let signal = latestSignal {
            print("MockPraise: trigger id=\(signal.id.uuidString)")
        }
        #endif
    }

    func clearPraise() {
        guard latestSignal != nil else { return }
        latestSignal = nil
        #if DEBUG
        print("MockPraise: clear")
        #endif
    }
}

private extension JSONValue {
    var boolValue: Bool? {
        if case let .bool(v) = self { return v }
        return nil
    }

    var intValue: Int? {
        if case let .number(v) = self { return Int(v) }
        return nil
    }

    var stringValue: String? {
        if case let .string(v) = self { return v }
        return nil
    }

    var arrayValue: [JSONValue]? {
        if case let .array(v) = self { return v }
        return nil
    }

    var objectValue: [String: JSONValue]? {
        if case let .object(v) = self { return v }
        return nil
    }
}
