import SwiftUI
import Foundation

struct SettingsSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var showingExportSheet = false
    @State private var exportItems: [Any] = []
    @State private var isExporting = false

    @State private var showAlert = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""

    var body: some View {
        NavigationStack {
            List {
                Section("Settings") {
                    Text("MVP shell")

                    Button {
                        guard !isExporting else { return }
                        isExporting = true
                        let exporter = DiagnosticsExporter()

                        DispatchQueue.global(qos: .utility).async {
                            do {
                                let exportURL = try exporter.exportDiagnosticsFile()
                                let item: Any
                                if let provider = NSItemProvider(contentsOf: exportURL) {
                                    provider.suggestedName = exportURL.lastPathComponent
                                    item = provider
                                } else {
                                    item = exportURL
                                }

                                DispatchQueue.main.async {
                                    self.exportItems = [item]
                                    self.showingExportSheet = true
                                    self.isExporting = false
                                }
                            } catch {
                                DispatchQueue.main.async {
                                    self.alertTitle = "Export failed"
                                    self.alertMessage = error.localizedDescription
                                    self.showAlert = true
                                    self.isExporting = false
                                }
                            }
                        }
                    } label: {
                        if isExporting {
                            HStack(spacing: 8) {
                                ProgressView()
                                Text("Exporting Diagnostics Logs...")
                            }
                        } else {
                            Text("Export Diagnostics Logs")
                        }
                    }
                    .disabled(isExporting)
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
        .promptHost()
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
