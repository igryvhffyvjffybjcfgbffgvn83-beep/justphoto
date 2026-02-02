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
}

#Preview {
    NavigationStack { DebugToolsScreen() }
}

#endif
