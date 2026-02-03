import SwiftUI

struct PaywallSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Text("Paywall")
                    .font(.title.bold())
                Text("MVP shell")
                    .foregroundStyle(.secondary)
            }
            .padding()
            .navigationTitle("Pro")
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
    PaywallSheet()
}
