import Foundation

struct DiagnosticsEvent: Codable, Sendable {
    let ts_ms: Int64
    let session_id: String
    let event: String
    let scene: String
    let payload: [String: String]

    static func makeTestEvent(now: Date = .init()) -> DiagnosticsEvent {
        DiagnosticsEvent(
            ts_ms: Int64(now.timeIntervalSince1970 * 1000),
            session_id: "dev_session",
            event: "test_event",
            scene: "cafe",
            payload: [
                "source": "debug_tools"
            ]
        )
    }
}
