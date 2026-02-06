import Foundation

// Stores thumbnail cache files under Application Support/JustPhoto/thumbcache.
// The database stores `thumb_cache_rel_path` relative to Application Support/JustPhoto.
// Example: thumbcache/<itemId>.jpg
final class ThumbCacheStore: Sendable {
    nonisolated static let shared = ThumbCacheStore()
    private nonisolated init() {}

    nonisolated func thumbCacheDirectoryURL(appSubdirName: String = "JustPhoto") throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dir = base
            .appendingPathComponent(appSubdirName, isDirectory: true)
            .appendingPathComponent("thumbcache", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    nonisolated func makeRelativePath(itemId: String, fileExtension: String = "jpg") -> String {
        let safeExt = fileExtension.isEmpty ? "bin" : fileExtension
        return "thumbcache/\(itemId).\(safeExt)"
    }

    @discardableResult
    nonisolated func writeAtomic(data: Data, toRelativePath relPath: String, appSubdirName: String = "JustPhoto") throws -> URL {
        // Reuse PendingFileStore's base path + sanitization.
        let destURL = try PendingFileStore.shared.fullURL(forRelativePath: relPath, appSubdirName: appSubdirName)

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
        let url = try PendingFileStore.shared.fullURL(forRelativePath: relPath, appSubdirName: appSubdirName)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
            return true
        }
        return false
    }

    nonisolated func fileExists(relativePath relPath: String, appSubdirName: String = "JustPhoto") -> Bool {
        guard let url = try? PendingFileStore.shared.fullURL(forRelativePath: relPath, appSubdirName: appSubdirName) else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }
}
