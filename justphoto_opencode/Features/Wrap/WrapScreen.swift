import SwiftUI

struct WrapScreen: View {
    var body: some View {
        VStack(spacing: 12) {
            Text("Wrap")
                .font(.title.bold())
            Text("MVP shell")
                .foregroundStyle(.secondary)
        }
        .padding()
        .navigationTitle("Wrap")
        .promptHost()
    }
}

#Preview {
    NavigationStack { WrapScreen() }
        .environmentObject(PromptCenter())
}
