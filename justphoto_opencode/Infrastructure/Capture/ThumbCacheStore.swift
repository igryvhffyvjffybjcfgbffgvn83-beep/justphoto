import Foundation

// Stores thumbnail cache files under Caches/JustPhoto/thumbcache.
// The database stores `thumb_cache_rel_path` relative to Caches/JustPhoto.
// Example: thumbcache/<itemId>.jpg
final class ThumbCacheStore: Sendable {
    nonisolated static let shared = ThumbCacheStore()
    private nonisolated init() {}

    nonisolated func thumbCacheDirectoryURL(appSubdirName: String = "JustPhoto") throws -> URL {
        let base = try FileManager.default.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dir = base
            .appendingPathComponent(appSubdirName, isDirectory: true)
            .appendingPathComponent("thumbcache", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        try migrateLegacyThumbCacheIfNeeded(newThumbDir: dir, appSubdirName: appSubdirName)
        return dir
    }

    nonisolated func makeRelativePath(itemId: String, fileExtension: String = "jpg") -> String {
        let safeExt = fileExtension.isEmpty ? "bin" : fileExtension
        return "thumbcache/\(itemId).\(safeExt)"
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

    nonisolated func fullURL(forRelativePath relPath: String, appSubdirName: String = "JustPhoto") throws -> URL {
        let base = try FileManager.default.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let cleaned = try sanitizeRelativePath(relPath)
        let root = base.appendingPathComponent(appSubdirName, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        if cleaned.hasPrefix("thumbcache/") {
            let thumbDir = root.appendingPathComponent("thumbcache", isDirectory: true)
            try FileManager.default.createDirectory(at: thumbDir, withIntermediateDirectories: true)
            try migrateLegacyThumbCacheIfNeeded(newThumbDir: thumbDir, appSubdirName: appSubdirName)
        }
        return root.appendingPathComponent(cleaned, isDirectory: false)
    }

    private nonisolated func sanitizeRelativePath(_ relPath: String) throws -> String {
        if relPath.hasPrefix("/") {
            throw NSError(domain: "ThumbCacheStore", code: 1)
        }

        let parts = relPath.split(separator: "/", omittingEmptySubsequences: true)
        if parts.isEmpty {
            throw NSError(domain: "ThumbCacheStore", code: 2)
        }
        if parts.contains("..") {
            throw NSError(domain: "ThumbCacheStore", code: 3)
        }

        return parts.joined(separator: "/")
    }

    private nonisolated func migrateLegacyThumbCacheIfNeeded(newThumbDir: URL, appSubdirName: String) throws {
        let legacyBase = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let legacyDir = legacyBase
            .appendingPathComponent(appSubdirName, isDirectory: true)
            .appendingPathComponent("thumbcache", isDirectory: true)

        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: legacyDir.path, isDirectory: &isDir), isDir.boolValue else {
            return
        }

        let entries = try FileManager.default.contentsOfDirectory(at: legacyDir, includingPropertiesForKeys: nil)
        guard !entries.isEmpty else {
            try? FileManager.default.removeItem(at: legacyDir)
            return
        }

        for src in entries {
            let dst = newThumbDir.appendingPathComponent(src.lastPathComponent, isDirectory: false)
            if FileManager.default.fileExists(atPath: dst.path) {
                continue
            }
            try? FileManager.default.moveItem(at: src, to: dst)
        }

        // Best-effort cleanup: remove legacy directory if it's now empty.
        if let remaining = try? FileManager.default.contentsOfDirectory(atPath: legacyDir.path), remaining.isEmpty {
            try? FileManager.default.removeItem(at: legacyDir)
        }
    }
}
