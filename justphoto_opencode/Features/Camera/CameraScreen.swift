import SwiftUI

struct CameraScreen: View {
    @EnvironmentObject private var promptCenter: PromptCenter

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

#if DEBUG
                Button("ShowTestToast (Camera)") {
                    promptCenter.show(
                        Prompt(
                            key: "debug_toast_camera",
                            level: .L1,
                            surface: .cameraToastBottom,
                            priority: 10,
                            blocksShutter: false,
                            isClosable: false,
                            autoDismissSeconds: 2.0,
                            gate: .none,
                            title: nil,
                            message: "Toast OK (Camera)",
                            primaryActionId: nil,
                            primaryTitle: nil,
                            secondaryActionId: nil,
                            secondaryTitle: nil,
                            tertiaryActionId: nil,
                            tertiaryTitle: nil,
                            throttle: .init(
                                perKeyMinIntervalSec: 0,
                                globalWindowSec: 0,
                                globalMaxCountInWindow: 0,
                                suppressAfterDismissSec: 0
                            ),
                            payload: [:],
                            emittedAt: Date()
                        )
                    )
                }
                .buttonStyle(.bordered)
#endif

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
        .environmentObject(PromptCenter())
}
