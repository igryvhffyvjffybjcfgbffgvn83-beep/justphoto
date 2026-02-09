import Foundation
import Combine

struct PromptActionEvent: Sendable, Equatable {
    var promptKey: String
    var actionId: String
}

@MainActor
final class PromptCenter: ObservableObject {
    @Published private(set) var toast: Prompt?
    @Published private(set) var banner: Prompt?
    @Published private(set) var modal: Prompt?

    private let actionSubject = PassthroughSubject<PromptActionEvent, Never>()
    var actionPublisher: AnyPublisher<PromptActionEvent, Never> {
        actionSubject.eraseToAnyPublisher()
    }

    private let diagnostics = DiagnosticsEventWriter.shared

    func show(_ prompt: Prompt) {
        if shouldSuppressBeforeShow(prompt) {
            return
        }

        switch prompt.level {
        case .L1:
            let chosen = choose(existing: toast, incoming: prompt, slot: "toast")
            toast = chosen
            if chosen == prompt {
                didShow(prompt)
                logPromptShown(prompt)
            }
        case .L2:
            let chosen = choose(existing: banner, incoming: prompt, slot: "banner")
            banner = chosen
            if chosen == prompt {
                didShow(prompt)
                logPromptShown(prompt)
            }
        case .L3:
            let chosen = choose(existing: modal, incoming: prompt, slot: "modal")
            modal = chosen
            if chosen == prompt {
                didShow(prompt)
                logPromptShown(prompt)
            }
        }
    }

    private func shouldSuppressBeforeShow(_ prompt: Prompt) -> Bool {
        switch prompt.gate {
        case .sessionOnce:
            let key = PromptGateFlagKeys.sessionOnce(promptKey: prompt.key)
            do {
                if try SessionRepository.shared.sessionFlagBool(key) {
                    JPDebugPrint("PromptGated:\(prompt.key) gate=sessionOnce")
                    return true
                }
            } catch {
                // Prefer showing the prompt over suppressing it if gating fails.
                JPDebugPrint("PromptGateCheckFAILED:\(prompt.key) gate=sessionOnce error=\(error)")
            }
            return false
        case .none, .installOnce, .stateOnly:
            return false
        }
    }

    private func didShow(_ prompt: Prompt) {
        switch prompt.gate {
        case .sessionOnce:
            let key = PromptGateFlagKeys.sessionOnce(promptKey: prompt.key)
            do {
                try SessionRepository.shared.setSessionFlagBool(key, value: true)
            } catch {
                JPDebugPrint("PromptGateWriteFAILED:\(prompt.key) gate=sessionOnce error=\(error)")
            }
        case .none, .installOnce, .stateOnly:
            break
        }
    }

    func actionTapped(prompt: Prompt, actionId: String) {
        JPDebugPrint("PromptActionTapped:\(prompt.key) action=\(actionId)")
        logPromptActionTapped(prompt, actionId: actionId)
        actionSubject.send(.init(promptKey: prompt.key, actionId: actionId))

        switch prompt.level {
        case .L1:
            guard toast?.id == prompt.id else { return }
            dismissToast(reason: .action)
        case .L2:
            guard banner?.id == prompt.id else { return }
            dismissBanner(reason: .action)
        case .L3:
            guard modal?.id == prompt.id else { return }
            dismissModal(reason: .action)
        }
    }

    func dismissModal(reason: DismissReason) {
        guard let existing = modal else { return }
        JPDebugPrint("PromptDismissed:\(existing.key) reason=\(reason.rawValue)")
        logPromptDismissed(existing, reason: reason)
        modal = nil
    }

    func dismissToast(reason: DismissReason) {
        guard let existing = toast else { return }
        JPDebugPrint("PromptDismissed:\(existing.key) reason=\(reason.rawValue)")
        logPromptDismissed(existing, reason: reason)
        toast = nil
    }

    func dismissBanner(reason: DismissReason) {
        guard let existing = banner else { return }
        JPDebugPrint("PromptDismissed:\(existing.key) reason=\(reason.rawValue)")
        logPromptDismissed(existing, reason: reason)
        banner = nil
    }

    private func choose(existing: Prompt?, incoming: Prompt, slot: String) -> Prompt {
        guard let existing else { return incoming }

        if incoming.priority > existing.priority {
            preempt(existing: existing, incoming: incoming)
            return incoming
        }

        if incoming.priority == existing.priority {
            if incoming.emittedAt >= existing.emittedAt {
                preempt(existing: existing, incoming: incoming)
                return incoming
            }
        }

        JPDebugPrint("PromptIgnored:\(incoming.key) slot=\(slot)")
        return existing
    }

    private func preempt(existing: Prompt, incoming: Prompt) {
        JPDebugPrint("PromptPreempted:\(existing.key)->\(incoming.key)")
        JPDebugPrint("PromptDismissed:\(existing.key) reason=\(DismissReason.preempt.rawValue)")
        logPromptDismissed(existing, reason: .preempt)
    }

    private func diagnosticsContext() -> (sessionId: String, scene: String)? {
        if let current = try? SessionRepository.shared.loadCurrentSession() {
            return (sessionId: current.sessionId, scene: current.scene)
        }
        if let sessionId = try? SessionRepository.shared.currentSessionId() {
            return (sessionId: sessionId, scene: "cafe")
        }
        if let sessionId = try? SessionRepository.shared.createNewSession(scene: "cafe") {
            return (sessionId: sessionId, scene: "cafe")
        }
        return nil
    }

    private func logPromptShown(_ prompt: Prompt) {
        guard let ctx = diagnosticsContext() else { return }
        Task {
            await diagnostics.logPromptShown(sessionId: ctx.sessionId, scene: ctx.scene, prompt: prompt)
        }
    }

    private func logPromptDismissed(_ prompt: Prompt, reason: DismissReason) {
        guard let ctx = diagnosticsContext() else { return }
        Task {
            await diagnostics.logPromptDismissed(sessionId: ctx.sessionId, scene: ctx.scene, prompt: prompt, dismissReason: reason)
        }
    }

    private func logPromptActionTapped(_ prompt: Prompt, actionId: String) {
        guard let ctx = diagnosticsContext() else { return }
        Task {
            await diagnostics.logPromptActionTapped(sessionId: ctx.sessionId, scene: ctx.scene, prompt: prompt, actionId: actionId)
        }
    }
}
