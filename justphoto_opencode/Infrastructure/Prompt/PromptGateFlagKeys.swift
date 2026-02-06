import Foundation

// Keys stored in sessions.flags_json for Prompt frequency gates.
enum PromptGateFlagKeys {
    static func sessionOnce(promptKey: String) -> String {
        "prompt.session_once.\(promptKey)"
    }
}
