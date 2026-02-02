import SwiftUI

struct ViewerScreen: View {
    var body: some View {
        VStack(spacing: 12) {
            Text("Viewer")
                .font(.title.bold())
            Text("MVP shell")
                .foregroundStyle(.secondary)
        }
        .padding()
        .navigationTitle("Viewer")
    }
}

#Preview {
    NavigationStack { ViewerScreen() }
}
