import Foundation

final class DiagnosticsLogger: Sendable {
    init() {}

    func encodeJSONLine(_ event: DiagnosticsEvent) throws -> String {
        let data = try JSONEncoder().encode(event)
        guard let line = String(data: data, encoding: .utf8) else {
            throw NSError(domain: "DiagnosticsLogger", code: 1)
        }
        return line
    }

    func currentLogFileURL() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )

        let dir = base.appendingPathComponent("JustPhoto", isDirectory: true)
            .appendingPathComponent("Diagnostics", isDirectory: true)

        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("diagnostics.jsonl", isDirectory: false)
    }

    func fileSizeBytes(at url: URL) -> Int64 {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        return Int64(values?.fileSize ?? 0)
    }

    @discardableResult
    func appendJSONLine(_ jsonLine: String) throws -> (fileURL: URL, bytesBefore: Int64, bytesAfter: Int64) {
        let url = try currentLogFileURL()
        let before = fileSizeBytes(at: url)

        let line = jsonLine + "\n"
        let data = Data(line.utf8)

        if FileManager.default.fileExists(atPath: url.path) {
            let handle = try FileHandle(forWritingTo: url)
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
            try handle.close()
        } else {
            try data.write(to: url, options: Data.WritingOptions.atomic)
        }

        let after = fileSizeBytes(at: url)
        return (fileURL: url, bytesBefore: before, bytesAfter: after)
    }
}
