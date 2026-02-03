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

private struct PromptBannerView: View {
    @EnvironmentObject private var promptCenter: PromptCenter
    let prompt: Prompt

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                if let title = prompt.title, !title.isEmpty {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                }

                Text(prompt.message)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
            }

            Spacer(minLength: 0)

            if let primaryTitle = prompt.primaryTitle, !primaryTitle.isEmpty {
                Button(primaryTitle) {
                    print("BannerPrimaryTapped")
                    promptCenter.dismissBanner(reason: .action)
                }
                .buttonStyle(.bordered)
            }

            if prompt.isClosable {
                Button {
                    promptCenter.dismissBanner(reason: .close)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(6)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.systemBackground).opacity(0.95))
                .shadow(color: .black.opacity(0.12), radius: 14, x: 0, y: 10)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.black.opacity(0.06), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel((prompt.title ?? "") + " " + prompt.message)
    }
}

private struct PromptHostOverlay: View {
    @EnvironmentObject private var promptCenter: PromptCenter

    var body: some View {
        VStack(spacing: 0) {
            if let banner = promptCenter.banner {
                PromptBannerView(prompt: banner)
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            Spacer(minLength: 0)

            if let toast = promptCenter.toast {
                PromptToastView(prompt: toast)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 18)
                    .allowsHitTesting(false)
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
        .animation(.spring(response: 0.28, dampingFraction: 0.9), value: promptCenter.toast?.id)
        .animation(.spring(response: 0.28, dampingFraction: 0.9), value: promptCenter.banner?.id)
    }
}

extension View {
    func promptHost() -> some View {
        modifier(PromptHostModifier())
    }
}

private struct PromptHostModifier: ViewModifier {
    @Environment(\.promptHostInstalled) private var installed

    func body(content: Content) -> some View {
        if installed {
            content
        } else {
            content
                .environment(\.promptHostInstalled, true)
                .overlay { PromptHostOverlay() }
        }
    }
}

private struct PromptHostInstalledKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

extension EnvironmentValues {
    var promptHostInstalled: Bool {
        get { self[PromptHostInstalledKey.self] }
        set { self[PromptHostInstalledKey.self] = newValue }
    }
}

#Preview {
    ContentView()
        .environmentObject(PromptCenter())
}
