import SwiftUI

struct SettingsSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Settings") {
                    Text("MVP shell")
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
    }
}

#Preview {
    SettingsSheet()
}
