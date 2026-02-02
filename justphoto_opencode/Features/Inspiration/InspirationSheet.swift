import SwiftUI

struct InspirationSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Text("Inspiration")
                    .font(.title.bold())
                Text("MVP shell")
                    .foregroundStyle(.secondary)
            }
            .padding()
            .navigationTitle("No ideas?")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    InspirationSheet()
}
