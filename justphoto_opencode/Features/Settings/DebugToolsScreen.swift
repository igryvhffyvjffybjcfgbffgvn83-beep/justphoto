#if DEBUG

import Foundation
import SwiftUI

struct DebugToolsScreen: View {
    @State private var statusText: String = ""
    @State private var statusIsError: Bool = false
    @State private var isRunning: Bool = false

    @State private var showAlert: Bool = false
    @State private var alertTitle: String = ""
    @State private var alertMessage: String = ""

    var body: some View {
        List {
            Section("Debug Tools") {
                Button("DebugToolsPing") {
                    print("DebugToolsPing")
                }

                Button("PrintDiagnosticsPath") {
                    do {
                        let logger = DiagnosticsLogger()
                        let dir = try logger.diagnosticsDirectoryURL()
                        let file = try logger.currentLogFileURL()

                        print("DiagnosticsDirectory: \(dir.path)")
                        print("DiagnosticsPath: \(file.path)")

                        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
                        if !names.isEmpty {
                            print("DiagnosticsFiles: \(names.sorted())")
                        }

                        statusText = "DiagnosticsDirectory:\n\(dir.path)\n\nDiagnosticsPath:\n\(file.path)"
                        statusIsError = false
                        alertTitle = "Diagnostics path"
                        alertMessage = file.path
                        showAlert = true
                    } catch {
                        statusText = "PrintDiagnosticsPath: FAILED\n\(error.localizedDescription)"
                        statusIsError = true
                        alertTitle = "Diagnostics path failed"
                        alertMessage = error.localizedDescription
                        showAlert = true
                    }
                }

                Button("SpamDiagnostics") {
                    guard !isRunning else { return }
                    isRunning = true
                    statusText = "SpamDiagnostics: running..."
                    statusIsError = false

                    Task {
                        let result = spamDiagnostics()
                        await MainActor.run {
                            isRunning = false
                            statusText = result.statusText
                            statusIsError = !result.ok
                            alertTitle = result.ok ? "SpamDiagnostics done" : "SpamDiagnostics failed"
                            alertMessage = result.alertMessage
                            showAlert = true
                        }
                    }
                }
                .disabled(isRunning)

                Button {
                    guard !isRunning else { return }
                    isRunning = true
                    statusText = "WriteTestDiagnostic: running..."
                    statusIsError = false
                    print("WriteTestDiagnosticTapped")

                    Task {
                        let result = writeTestDiagnostic()
                        await MainActor.run {
                            isRunning = false
                            statusText = result.statusText
                            statusIsError = !result.ok
                            alertTitle = result.ok ? "Diagnostic generated" : "Diagnostic failed"
                            alertMessage = result.alertMessage
                            showAlert = true
                        }
                    }
                } label: {
                    HStack {
                        Text("WriteTestDiagnostic")
                        Spacer()
                        if isRunning {
                            ProgressView()
                        }
                    }
                }
                .disabled(isRunning)

                if !statusText.isEmpty {
                    Text(statusText)
                        .font(.footnote)
                        .foregroundStyle(statusIsError ? .red : .secondary)
                        .textSelection(.enabled)
                }

                Text("Debug-only tools live here")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Debug Tools")
        .alert(alertTitle, isPresented: $showAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertMessage)
        }
    }

    private func writeTestDiagnostic() -> (ok: Bool, statusText: String, alertMessage: String) {
        let logger = DiagnosticsLogger()
        let event = DiagnosticsEvent.makeTestEvent()
        do {
            let line = try logger.encodeJSONLine(event)
            print(line)

            let appendResult = try logger.appendJSONLine(line)
            print("DiagnosticAppended")

            let data = Data(line.utf8)
            if let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let requiredKeys = ["ts_ms", "session_id", "event", "scene", "payload"]
                let ok = requiredKeys.allSatisfy { obj[$0] != nil }
                print(ok ? "DiagnosticEventFieldsOK" : "DiagnosticEventFieldsMISSING")

                if ok {
                    return (
                        ok: true,
                        statusText: "WriteTestDiagnostic: OK\n\nfile: \(appendResult.fileURL.path)\nbytes: \(appendResult.bytesBefore) -> \(appendResult.bytesAfter)\n\n\(line)",
                        alertMessage: "Success. A JSON line was appended (see file path in status)."
                    )
                } else {
                    return (
                        ok: false,
                        statusText: "WriteTestDiagnostic: FAILED (missing required fields)\n\nfile: \(appendResult.fileURL.path)\nbytes: \(appendResult.bytesBefore) -> \(appendResult.bytesAfter)\n\n\(line)",
                        alertMessage: "JSON generated, but required keys are missing."
                    )
                }
            } else {
                print("DiagnosticEventParseFAILED")
                return (
                    ok: false,
                    statusText: "WriteTestDiagnostic: FAILED (JSON parse failed)",
                    alertMessage: "Could not parse the encoded JSON line. Check console output."
                )
            }
        } catch {
            print("DiagnosticEventEncodeFAILED: \(error)")
            return (
                ok: false,
                statusText: "WriteTestDiagnostic: FAILED (encode error)",
                alertMessage: "Encode/parse failed: \(error.localizedDescription)"
            )
        }
    }

    private func spamDiagnostics() -> (ok: Bool, statusText: String, alertMessage: String) {
        do {
            let logger = DiagnosticsLogger()
            let file = try logger.currentLogFileURL()
            let dir = try logger.diagnosticsDirectoryURL()

            let rotation = DiagnosticsRotationManager(maxTotalBytes: 50 * 1024 * 1024)

            // Roughly ~1KB per line. Write enough to cross 50MB quickly, then rotate.
            // This is debug-only and used solely to validate size rotation.
            let payloadString = String(repeating: "x", count: 900)
            let targetLines = 80_000

            for i in 0..<targetLines {
                let event = DiagnosticsEvent(
                    ts_ms: Int64(Date().timeIntervalSince1970 * 1000),
                    session_id: "dev_session",
                    event: "spam",
                    scene: "cafe",
                    payload: [
                        "i": String(i),
                        "data": payloadString
                    ]
                )

                let line = try logger.encodeJSONLine(event)
                _ = try logger.appendJSONLine(line)

                if i % 2000 == 0 {
                    try rotation.rotateIfNeeded()
                }
            }

            try rotation.rotateIfNeeded()
            let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []

            return (
                ok: true,
                statusText: "SpamDiagnostics: OK\n\nDiagnosticsDirectory:\n\(dir.path)\n\nCurrentFile:\n\(file.path)",
                alertMessage: "Done. Check console for RotationBySizeTriggered and file list: \(names.sorted())"
            )
        } catch {
            return (
                ok: false,
                statusText: "SpamDiagnostics: FAILED\n\(error.localizedDescription)",
                alertMessage: error.localizedDescription
            )
        }
    }
}

#Preview {
    NavigationStack { DebugToolsScreen() }
}

#endif
