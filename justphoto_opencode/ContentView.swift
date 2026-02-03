//
//  ContentView.swift
//  justphoto_opencode
//
//  Created by 番茄 on 1/2/2026.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        CameraScreen()
            .promptHost()
    }
}

private struct PromptToastView: View {
    let prompt: Prompt

    var body: some View {
        Text(prompt.message)
            .font(.callout.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.black.opacity(0.88))
                    .shadow(color: .black.opacity(0.25), radius: 12, x: 0, y: 8)
            )
            .accessibilityLabel(prompt.message)
    }
}

private struct PromptHostOverlay: View {
    @EnvironmentObject private var promptCenter: PromptCenter

    var body: some View {
        ZStack(alignment: .bottom) {
            if let toast = promptCenter.toast {
                PromptToastView(prompt: toast)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 18)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .task(id: toast.id) {
                        guard let seconds = toast.autoDismissSeconds else { return }

                        let ns = UInt64(max(0.0, seconds) * 1_000_000_000)
                        do {
                            try await Task.sleep(nanoseconds: ns)
                        } catch {
                            return
                        }

                        if promptCenter.toast?.id == toast.id {
                            await MainActor.run {
                                promptCenter.dismissToast(reason: .auto)
                            }
                        }
                    }
            }
        }
        // Critical: ensure the overlay fills the host view. Without this, SwiftUI may
        // size the overlay to its content and the toast can effectively render off-screen.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .allowsHitTesting(false)
        .animation(.spring(response: 0.28, dampingFraction: 0.9), value: promptCenter.toast?.id)
    }
}

extension View {
    func promptHost() -> some View {
        overlay {
            PromptHostOverlay()
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(PromptCenter())
}
