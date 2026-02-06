import Foundation

enum AlbumState: String, Codable, Sendable, CaseIterable {
    case queued = "queued"
    case success = "success"
    case failed = "failed"
}
