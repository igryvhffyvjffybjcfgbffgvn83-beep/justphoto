import Foundation

// PRD Milestone 4.9: PendingFileStore
// - Location: Application Support/JustPhoto/pending
// - Atomic write: write tmp, then rename/replace
// - Deletion support
//
// The database stores `pending_file_rel_path` (relative to Application Support/JustPhoto).
// Example: pending/<itemId>.jpg
final class PendingFileStore: Sendable {
    nonisolated static let shared = PendingFileStore()

    private nonisolated init() {}

    nonisolated func justPhotoBaseDirectoryURL(appSubdirName: String = "JustPhoto") throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dir = base.appendingPathComponent(appSubdirName, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    nonisolated func pendingDirectoryURL(appSubdirName: String = "JustPhoto") throws -> URL {
        let base = try justPhotoBaseDirectoryURL(appSubdirName: appSubdirName)
        let dir = base.appendingPathComponent("pending", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    nonisolated func makeRelativePath(itemId: String, fileExtension: String = "jpg") -> String {
        let safeExt = fileExtension.isEmpty ? "bin" : fileExtension
        return "pending/\(itemId).\(safeExt)"
    }

    nonisolated func fullURL(forRelativePath relPath: String, appSubdirName: String = "JustPhoto") throws -> URL {
        let base = try justPhotoBaseDirectoryURL(appSubdirName: appSubdirName)
        let cleaned = try sanitizeRelativePath(relPath)
        return base.appendingPathComponent(cleaned, isDirectory: false)
    }

    @discardableResult
    nonisolated func writeAtomic(data: Data, toRelativePath relPath: String, appSubdirName: String = "JustPhoto") throws -> URL {
        let destURL = try fullURL(forRelativePath: relPath, appSubdirName: appSubdirName)

        let parent = destURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)

        let tmpName = ".tmp-\(UUID().uuidString)"
        let tmpURL = parent.appendingPathComponent(tmpName, isDirectory: false)

        try data.write(to: tmpURL, options: [])

        if FileManager.default.fileExists(atPath: destURL.path) {
            _ = try FileManager.default.replaceItemAt(destURL, withItemAt: tmpURL)
        } else {
            try FileManager.default.moveItem(at: tmpURL, to: destURL)
        }

        return destURL
    }

    @discardableResult
    nonisolated func delete(relativePath relPath: String, appSubdirName: String = "JustPhoto") throws -> Bool {
        let url = try fullURL(forRelativePath: relPath, appSubdirName: appSubdirName)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
            return true
        }
        return false
    }

    nonisolated func fileExists(relativePath relPath: String, appSubdirName: String = "JustPhoto") -> Bool {
        guard let url = try? fullURL(forRelativePath: relPath, appSubdirName: appSubdirName) else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    private nonisolated func sanitizeRelativePath(_ relPath: String) throws -> String {
        if relPath.hasPrefix("/") {
            throw NSError(domain: "PendingFileStore", code: 1)
        }

        let parts = relPath.split(separator: "/", omittingEmptySubsequences: true)
        if parts.isEmpty {
            throw NSError(domain: "PendingFileStore", code: 2)
        }
        if parts.contains("..") {
            throw NSError(domain: "PendingFileStore", code: 3)
        }

        // Rejoin to normalize repeated slashes.
        return parts.joined(separator: "/")
    }
}
