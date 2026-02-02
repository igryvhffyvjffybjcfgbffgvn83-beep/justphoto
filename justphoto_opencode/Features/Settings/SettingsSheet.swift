import SwiftUI

struct SettingsSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var showingExportSheet = false
    @State private var exportItems: [Any] = []

    @State private var showAlert = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""

    var body: some View {
        NavigationStack {
            List {
                Section("Settings") {
                    Text("MVP shell")

                    Button("Export Diagnostics Logs") {
                        do {
                            let exporter = DiagnosticsExporter()
                            let exportURL = try exporter.exportDiagnosticsFile()

                            // Prefer NSItemProvider so the share sheet consistently treats this
                            // as a file-backed item (esp. for Save to Files).
                            if let provider = NSItemProvider(contentsOf: exportURL) {
                                provider.suggestedName = exportURL.lastPathComponent
                                exportItems = [provider]
                            } else {
                                exportItems = [exportURL]
                            }
                            showingExportSheet = true
                        } catch {
                            alertTitle = "Export failed"
                            alertMessage = error.localizedDescription
                            showAlert = true
                        }
                    }
                }

#if DEBUG
                Section("Debug") {
                    NavigationLink("Debug Tools") {
                        DebugToolsScreen()
                    }
                }
#endif
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .sheet(isPresented: $showingExportSheet) {
            ShareSheet(activityItems: exportItems)
        }
        .alert(alertTitle, isPresented: $showAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertMessage)
        }
    }
}

#Preview {
    SettingsSheet()
}
