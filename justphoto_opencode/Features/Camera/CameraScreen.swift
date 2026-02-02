import SwiftUI

struct CameraScreen: View {
    @State private var showingSettings = false
    @State private var showingPaywall = false
    @State private var showingInspiration = false
    @State private var showingDownReasons = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("Camera")
                    .font(.title.bold())

                Text("MVP shell (no camera yet)")
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    Button("Settings") { showingSettings = true }
                    Button("Paywall") { showingPaywall = true }
                    Button("Inspiration") { showingInspiration = true }
                }

                HStack(spacing: 12) {
                    NavigationLink("Viewer") { ViewerScreen() }
                    NavigationLink("Wrap") { WrapScreen() }
                    Button("Down Reasons") { showingDownReasons = true }
                }

                Spacer(minLength: 0)
            }
            .padding()
            .navigationTitle("Just Photo")
        }
        .sheet(isPresented: $showingSettings) { SettingsSheet() }
        .sheet(isPresented: $showingPaywall) { PaywallSheet() }
        .sheet(isPresented: $showingInspiration) { InspirationSheet() }
        .sheet(isPresented: $showingDownReasons) { DownReasonsSheet() }
    }
}

#Preview {
    CameraScreen()
}
