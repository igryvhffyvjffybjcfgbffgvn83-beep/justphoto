import SwiftUI

struct DownReasonsSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Down Reasons") {
                    Text("MVP shell")
                }
            }
            .navigationTitle("Not good")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .promptHost()
    }
}

#Preview {
    DownReasonsSheet()
}
