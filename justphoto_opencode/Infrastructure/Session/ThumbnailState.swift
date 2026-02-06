import Foundation

enum ThumbnailState: String, Codable, Sendable, CaseIterable {
    case ready = "ready"
    case failed = "failed"
}
