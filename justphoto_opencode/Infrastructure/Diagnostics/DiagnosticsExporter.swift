import Foundation

struct DiagnosticsExporter: Sendable {
    enum ExportError: LocalizedError {
        case noLogs

        var errorDescription: String? {
            switch self {
            case .noLogs:
                return "No diagnostics logs yet. Generate one and try again."
            }
        }
    }

    func collectLogFiles() throws -> [URL] {
        let dir = try diagnosticsDirectoryURL()
        let fm = FileManager.default

        let urls = (try? fm.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        var files: [URL] = []
        files.reserveCapacity(urls.count)

        for url in urls where url.pathExtension.lowercased() == "jsonl" {
            files.append(url)
        }

        files.sort { $0.lastPathComponent < $1.lastPathComponent }

        guard !files.isEmpty else {
            throw ExportError.noLogs
        }

        return files
    }

    /// Creates a single export artifact (preferred) suitable for share sheets.
    ///
    /// Rationale: sharing in-place files from Application Support can be flaky across
    /// activity extensions; exporting to a temporary, single file is far more reliable.
    func exportDiagnosticsFile() throws -> URL {
        let files = try collectLogFiles()

        let fm = FileManager.default
        let tempBase = fm.temporaryDirectory
        let stamp = Self.exportTimestampString(now: Date())

        // Use a widely supported extension so Files/Share sheet always treats it as a document.
        let outURL = tempBase.appendingPathComponent("JustPhoto-Diagnostics-\(stamp).txt", isDirectory: false)
        if fm.fileExists(atPath: outURL.path) {
            try? fm.removeItem(at: outURL)
        }

        guard fm.createFile(atPath: outURL.path, contents: nil) else {
            throw CocoaError(.fileWriteUnknown)
        }

        let outHandle = try FileHandle(forWritingTo: outURL)
        defer { try? outHandle.close() }

        for file in files {
            try outHandle.write(contentsOf: Data("# file: \(file.lastPathComponent)\n".utf8))

            let inHandle = try FileHandle(forReadingFrom: file)
            defer { try? inHandle.close() }

            while true {
                let chunk = try inHandle.read(upToCount: 1024 * 1024) ?? Data()
                if chunk.isEmpty { break }
                try outHandle.write(contentsOf: chunk)
            }

            try outHandle.write(contentsOf: Data("\n".utf8))
        }

        try? Self.setNoProtectionIfPossible(url: outURL)
        return outURL
    }

    private func diagnosticsDirectoryURL() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )

        let dir = base.appendingPathComponent("JustPhoto", isDirectory: true)
            .appendingPathComponent("Diagnostics", isDirectory: true)

        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func exportTimestampString(now: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f.string(from: now)
    }

    private static func setNoProtectionIfPossible(url: URL) throws {
        // For exported artifacts, prefer being readable by activity extensions.
        // If the platform doesn't support it, silently ignore.
        do {
            try FileManager.default.setAttributes([.protectionKey: FileProtectionType.none], ofItemAtPath: url.path)
        } catch {
            // Best-effort.
            _ = error
        }
    }
}
