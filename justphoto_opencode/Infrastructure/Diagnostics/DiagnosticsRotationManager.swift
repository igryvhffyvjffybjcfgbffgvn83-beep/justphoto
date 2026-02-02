import Foundation

struct DiagnosticsRotationManager: Sendable {
    private let maxTotalBytes: Int64
    private let appSubdirName: String

    init(maxTotalBytes: Int64 = 50 * 1024 * 1024, appSubdirName: String = "JustPhoto") {
        self.maxTotalBytes = maxTotalBytes
        self.appSubdirName = appSubdirName
    }

    func rotateIfNeeded() throws {
        let dir = try diagnosticsDirectoryURL()
        let fm = FileManager.default

        let fileURLs = (try? fm.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        let candidates = fileURLs
            .filter { $0.pathExtension.lowercased() == "jsonl" }

        struct Entry {
            let url: URL
            let modifiedAt: Date
            let size: Int64
        }

        var entries: [Entry] = []
        entries.reserveCapacity(candidates.count)

        for url in candidates {
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            let modifiedAt = values?.contentModificationDate ?? .distantPast
            let size = Int64(values?.fileSize ?? 0)
            entries.append(Entry(url: url, modifiedAt: modifiedAt, size: size))
        }

        var total: Int64 = entries.reduce(0) { $0 + $1.size }
        guard total > maxTotalBytes else { return }

        entries.sort { a, b in
            if a.modifiedAt != b.modifiedAt { return a.modifiedAt < b.modifiedAt }
            return a.url.lastPathComponent < b.url.lastPathComponent
        }

        var deleted: [String] = []
        for e in entries {
            if total <= maxTotalBytes { break }
            do {
                try fm.removeItem(at: e.url)
                total -= e.size
                deleted.append(e.url.lastPathComponent)
            } catch {
                continue
            }
        }

        if !deleted.isEmpty {
            print("RotationBySizeTriggered")
            print("RotationDeletedFiles: \(deleted)")
            print("RotationTotalBytesAfter: \(total)")
        }
    }

    func deleteOldLogs(now: Date = .init(), maxAgeDays: Int = 30) throws {
        let dir = try diagnosticsDirectoryURL()
        let fm = FileManager.default

        let fileURLs = (try? fm.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        let cutoff = now.addingTimeInterval(TimeInterval(-maxAgeDays) * 24 * 60 * 60)

        struct Entry {
            let url: URL
            let modifiedAt: Date
        }

        var toDelete: [Entry] = []
        for url in fileURLs where url.pathExtension.lowercased() == "jsonl" {
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
            let modifiedAt = values?.contentModificationDate ?? .distantPast
            if modifiedAt < cutoff {
                toDelete.append(Entry(url: url, modifiedAt: modifiedAt))
            }
        }

        guard !toDelete.isEmpty else { return }

        toDelete.sort { a, b in
            if a.modifiedAt != b.modifiedAt { return a.modifiedAt < b.modifiedAt }
            return a.url.lastPathComponent < b.url.lastPathComponent
        }

        var deleted: [String] = []
        for e in toDelete {
            do {
                try fm.removeItem(at: e.url)
                deleted.append(e.url.lastPathComponent)
            } catch {
                continue
            }
        }

        if !deleted.isEmpty {
            print("RotationByAgeTriggered")
            print("RotationByAgeDeletedFiles: \(deleted)")
        }
    }

    private func diagnosticsDirectoryURL() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dir = base.appendingPathComponent(appSubdirName, isDirectory: true)
            .appendingPathComponent("Diagnostics", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
