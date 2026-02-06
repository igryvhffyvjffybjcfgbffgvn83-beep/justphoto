import Foundation

// Canonical session_item.state values used across the app.
enum SessionItemState: String, Codable, Sendable, CaseIterable {
    case captured_preview = "captured_preview"
    case writing = "writing"
    case write_failed = "write_failed"

    // Core lifecycle reached after PhotoKit write succeeds.
    // Thumbnail/album are tracked in separate columns.
    case finalized = "finalized"
}
