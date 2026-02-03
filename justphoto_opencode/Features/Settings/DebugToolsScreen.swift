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

                Button("CreateFakeOldLogs") {
                    guard !isRunning else { return }
                    isRunning = true
                    statusText = "CreateFakeOldLogs: running..."
                    statusIsError = false

                    Task {
                        let result = createFakeOldLogs()
                        await MainActor.run {
                            isRunning = false
                            statusText = result.statusText
                            statusIsError = !result.ok
                            alertTitle = result.ok ? "Fake logs created" : "CreateFakeOldLogs failed"
                            alertMessage = result.alertMessage
                            showAlert = true
                        }
                    }
                }
                .disabled(isRunning)

                Button("RunRotationNow") {
                    guard !isRunning else { return }
                    isRunning = true
                    statusText = "RunRotationNow: running..."
                    statusIsError = false

                    Task {
                        let result = runRotationNow()
                        await MainActor.run {
                            isRunning = false
                            statusText = result.statusText
                            statusIsError = !result.ok
                            alertTitle = result.ok ? "Rotation complete" : "RunRotationNow failed"
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

                Section("A.13 Required Events") {
                    Button("WriteA13 withref_match_state") {
                        guard !isRunning else { return }
                        isRunning = true
                        statusText = "WriteA13 withref_match_state: running..."
                        statusIsError = false

                        Task {
                            let result = writeA13_withrefMatchState()
                            await MainActor.run {
                                isRunning = false
                                statusText = result.statusText
                                statusIsError = !result.ok
                                alertTitle = result.ok ? "A.13 event written" : "A.13 event failed"
                                alertMessage = result.alertMessage
                                showAlert = true
                            }
                        }
                    }
                    .disabled(isRunning)

                    Button("WriteA13 withref_fallback") {
                        guard !isRunning else { return }
                        isRunning = true
                        statusText = "WriteA13 withref_fallback: running..."
                        statusIsError = false

                        Task {
                            let result = writeA13_withrefFallback()
                            await MainActor.run {
                                isRunning = false
                                statusText = result.statusText
                                statusIsError = !result.ok
                                alertTitle = result.ok ? "A.13 event written" : "A.13 event failed"
                                alertMessage = result.alertMessage
                                showAlert = true
                            }
                        }
                    }
                    .disabled(isRunning)

                    Button("WriteA13 photo_write_verification") {
                        guard !isRunning else { return }
                        isRunning = true
                        statusText = "WriteA13 photo_write_verification: running..."
                        statusIsError = false

                        Task {
                            let result = writeA13_photoWriteVerification()
                            await MainActor.run {
                                isRunning = false
                                statusText = result.statusText
                                statusIsError = !result.ok
                                alertTitle = result.ok ? "A.13 event written" : "A.13 event failed"
                                alertMessage = result.alertMessage
                                showAlert = true
                            }
                        }
                    }
                    .disabled(isRunning)

                    Button("WriteA13 phantom_asset_detected") {
                        guard !isRunning else { return }
                        isRunning = true
                        statusText = "WriteA13 phantom_asset_detected: running..."
                        statusIsError = false

                        Task {
                            let result = writeA13_phantomAssetDetected()
                            await MainActor.run {
                                isRunning = false
                                statusText = result.statusText
                                statusIsError = !result.ok
                                alertTitle = result.ok ? "A.13 event written" : "A.13 event failed"
                                alertMessage = result.alertMessage
                                showAlert = true
                            }
                        }
                    }
                    .disabled(isRunning)

                    Button("WriteA13 odr_auto_retry") {
                        guard !isRunning else { return }
                        isRunning = true
                        statusText = "WriteA13 odr_auto_retry: running..."
                        statusIsError = false

                        Task {
                            let result = writeA13_odrAutoRetry()
                            await MainActor.run {
                                isRunning = false
                                statusText = result.statusText
                                statusIsError = !result.ok
                                alertTitle = result.ok ? "A.13 event written" : "A.13 event failed"
                                alertMessage = result.alertMessage
                                showAlert = true
                            }
                        }
                    }
                    .disabled(isRunning)
                }

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

    private func createFakeOldLogs() -> (ok: Bool, statusText: String, alertMessage: String) {
        do {
            let logger = DiagnosticsLogger()
            let dir = try logger.diagnosticsDirectoryURL()

            let oldDate = Date().addingTimeInterval(-40 * 24 * 60 * 60)
            let recentDate = Date().addingTimeInterval(-2 * 24 * 60 * 60)

            let old1 = dir.appendingPathComponent("fake-old-1.jsonl")
            let old2 = dir.appendingPathComponent("fake-old-2.jsonl")
            let recent = dir.appendingPathComponent("fake-recent.jsonl")

            try Data("{}\n".utf8).write(to: old1, options: Data.WritingOptions.atomic)
            try Data("{}\n".utf8).write(to: old2, options: Data.WritingOptions.atomic)
            try Data("{}\n".utf8).write(to: recent, options: Data.WritingOptions.atomic)

            try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: old1.path)
            try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: old2.path)
            try FileManager.default.setAttributes([.modificationDate: recentDate], ofItemAtPath: recent.path)

            print("CreateFakeOldLogsCreated: \([old1.lastPathComponent, old2.lastPathComponent, recent.lastPathComponent])")

            let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
            return (
                ok: true,
                statusText: "CreateFakeOldLogs: OK\n\nDiagnosticsDirectory:\n\(dir.path)\n\nFiles:\n\(names.sorted().joined(separator: "\n"))",
                alertMessage: "Created 2 old logs (~40d) and 1 recent (~2d)."
            )
        } catch {
            return (
                ok: false,
                statusText: "CreateFakeOldLogs: FAILED\n\(error.localizedDescription)",
                alertMessage: error.localizedDescription
            )
        }
    }

    private func runRotationNow() -> (ok: Bool, statusText: String, alertMessage: String) {
        do {
            let logger = DiagnosticsLogger()
            let dir = try logger.diagnosticsDirectoryURL()
            let rotation = DiagnosticsRotationManager(maxTotalBytes: 50 * 1024 * 1024)

            try rotation.deleteOldLogs(now: Date(), maxAgeDays: 30)

            let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
            return (
                ok: true,
                statusText: "RunRotationNow: OK\n\nRemaining files:\n\(names.sorted().joined(separator: "\n"))",
                alertMessage: "Check console for RotationByAgeDeletedFiles."
            )
        } catch {
            return (
                ok: false,
                statusText: "RunRotationNow: FAILED\n\(error.localizedDescription)",
                alertMessage: error.localizedDescription
            )
        }
    }

    private func writeA13_withrefMatchState() -> (ok: Bool, statusText: String, alertMessage: String) {
        do {
            let logger = DiagnosticsLogger()
            let result = try logger.logWithRefMatchState(
                sessionId: "dev_session",
                scene: "cafe",
                match: false,
                requiredDimensions: ["centerXOffset", "centerYOffset"],
                blockedBy: ["centerXOffset"],
                mirrorApplied: true
            )
            print(result.jsonLine)
            print("A13EventWritten: withref_match_state")
            return (
                ok: true,
                statusText: "WriteA13 withref_match_state: OK\n\nfile: \(result.fileURL.path)\n\n\(result.jsonLine)",
                alertMessage: "Appended withref_match_state to diagnostics log."
            )
        } catch {
            print("A13EventWriteFAILED: withref_match_state: \(error)")
            return (
                ok: false,
                statusText: "WriteA13 withref_match_state: FAILED\n\(error.localizedDescription)",
                alertMessage: error.localizedDescription
            )
        }
    }

    private func writeA13_withrefFallback() -> (ok: Bool, statusText: String, alertMessage: String) {
        do {
            let logger = DiagnosticsLogger()
            let result = try logger.logWithRefFallback(
                sessionId: "dev_session",
                scene: "cafe",
                reason: "missing_eyeROI",
                missing: ["eyeROI"]
            )
            print(result.jsonLine)
            print("A13EventWritten: withref_fallback")
            return (
                ok: true,
                statusText: "WriteA13 withref_fallback: OK\n\nfile: \(result.fileURL.path)\n\n\(result.jsonLine)",
                alertMessage: "Appended withref_fallback to diagnostics log."
            )
        } catch {
            print("A13EventWriteFAILED: withref_fallback: \(error)")
            return (
                ok: false,
                statusText: "WriteA13 withref_fallback: FAILED\n\(error.localizedDescription)",
                alertMessage: error.localizedDescription
            )
        }
    }

    private func writeA13_photoWriteVerification() -> (ok: Bool, statusText: String, alertMessage: String) {
        do {
            let logger = DiagnosticsLogger()
            let result = try logger.logPhotoWriteVerification(
                sessionId: "dev_session",
                scene: "cafe",
                assetId: "debug_asset_id",
                firstFetchMs: 12,
                retryUsed: true,
                retryDelayMs: 500,
                verifiedWithin2s: true
            )
            print(result.jsonLine)
            print("A13EventWritten: photo_write_verification")
            return (
                ok: true,
                statusText: "WriteA13 photo_write_verification: OK\n\nfile: \(result.fileURL.path)\n\n\(result.jsonLine)",
                alertMessage: "Appended photo_write_verification to diagnostics log."
            )
        } catch {
            print("A13EventWriteFAILED: photo_write_verification: \(error)")
            return (
                ok: false,
                statusText: "WriteA13 photo_write_verification: FAILED\n\(error.localizedDescription)",
                alertMessage: error.localizedDescription
            )
        }
    }

    private func writeA13_phantomAssetDetected() -> (ok: Bool, statusText: String, alertMessage: String) {
        do {
            let logger = DiagnosticsLogger()
            let result = try logger.logPhantomAssetDetected(
                sessionId: "dev_session",
                scene: "cafe",
                assetIdHash: "debug_hash",
                authSnapshot: "limited",
                healAction: "pruned"
            )
            print(result.jsonLine)
            print("A13EventWritten: phantom_asset_detected")
            return (
                ok: true,
                statusText: "WriteA13 phantom_asset_detected: OK\n\nfile: \(result.fileURL.path)\n\n\(result.jsonLine)",
                alertMessage: "Appended phantom_asset_detected to diagnostics log."
            )
        } catch {
            print("A13EventWriteFAILED: phantom_asset_detected: \(error)")
            return (
                ok: false,
                statusText: "WriteA13 phantom_asset_detected: FAILED\n\(error.localizedDescription)",
                alertMessage: error.localizedDescription
            )
        }
    }

    private func writeA13_odrAutoRetry() -> (ok: Bool, statusText: String, alertMessage: String) {
        do {
            let logger = DiagnosticsLogger()
            let result = try logger.logODRAutoRetry(
                sessionId: "dev_session",
                scene: "cafe",
                stateBefore: "failed_retry",
                debounceMs: 500,
                result: "success"
            )
            print(result.jsonLine)
            print("A13EventWritten: odr_auto_retry")
            return (
                ok: true,
                statusText: "WriteA13 odr_auto_retry: OK\n\nfile: \(result.fileURL.path)\n\n\(result.jsonLine)",
                alertMessage: "Appended odr_auto_retry to diagnostics log."
            )
        } catch {
            print("A13EventWriteFAILED: odr_auto_retry: \(error)")
            return (
                ok: false,
                statusText: "WriteA13 odr_auto_retry: FAILED\n\(error.localizedDescription)",
                alertMessage: error.localizedDescription
            )
        }
    }
}

#Preview {
    NavigationStack { DebugToolsScreen() }
}

#endif
