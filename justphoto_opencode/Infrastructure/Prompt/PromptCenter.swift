import Foundation
import Combine

@MainActor
final class PromptCenter: ObservableObject {
    @Published private(set) var toast: Prompt?
    @Published private(set) var banner: Prompt?
    @Published private(set) var modal: Prompt?

    func show(_ prompt: Prompt) {
        switch prompt.level {
        case .L1:
            toast = choose(existing: toast, incoming: prompt, slot: "toast")
        case .L2:
            banner = choose(existing: banner, incoming: prompt, slot: "banner")
        case .L3:
            modal = choose(existing: modal, incoming: prompt, slot: "modal")
        }
    }

    func dismissModal(reason: DismissReason) {
        guard let existing = modal else { return }
        print("PromptDismissed:\(existing.key) reason=\(reason.rawValue)")
        modal = nil
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

        print("PromptIgnored:\(incoming.key) slot=\(slot)")
        return existing
    }

    private func preempt(existing: Prompt, incoming: Prompt) {
        print("PromptPreempted:\(existing.key)->\(incoming.key)")
        print("PromptDismissed:\(existing.key) reason=\(DismissReason.preempt.rawValue)")
    }
}
