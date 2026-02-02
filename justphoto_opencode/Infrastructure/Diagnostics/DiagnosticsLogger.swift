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
}
