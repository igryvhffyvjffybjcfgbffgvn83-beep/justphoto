//
//  ContentView.swift
//  justphoto_opencode
//
//  Created by 番茄 on 1/2/2026.
//

import SwiftUI
import UIKit

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
                    let actionId = prompt.primaryActionId ?? "primary"
                    promptCenter.actionTapped(prompt: prompt, actionId: actionId)
                }
                .buttonStyle(.bordered)
            }

            if let secondaryTitle = prompt.secondaryTitle, !secondaryTitle.isEmpty {
                Button(secondaryTitle) {
                    let actionId = prompt.secondaryActionId ?? "secondary"
                    promptCenter.actionTapped(prompt: prompt, actionId: actionId)
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

private struct PromptModalView: View {
    @EnvironmentObject private var promptCenter: PromptCenter
    let prompt: Prompt

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    if let title = prompt.title, !title.isEmpty {
                        Text(title)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.primary)
                    }

                    Text(prompt.message)
                        .font(.body)
                        .foregroundStyle(.primary)
                }

                Spacer(minLength: 0)

                if prompt.isClosable {
                    Button {
                        promptCenter.dismissModal(reason: .close)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(8)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close")
                }
            }

#if DEBUG
            if prompt.key == "A" {
                Button("Preempt to Test B") {
                    promptCenter.show(
                        Prompt(
                            key: "B",
                            level: .L3,
                            surface: .sheetModalCenter,
                            priority: 80,
                            blocksShutter: false,
                            isClosable: false,
                            autoDismissSeconds: nil,
                            gate: .none,
                            title: "Test B",
                            message: "This is a test modal (B).",
                            primaryActionId: "primary",
                            primaryTitle: "OK",
                            secondaryActionId: "secondary",
                            secondaryTitle: "Cancel",
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
            }
#endif

            VStack(alignment: .leading, spacing: 10) {
                ForEach(prompt.actions) { action in
                    if action.id == prompt.primaryActionId {
                        Button(action.title) {
                            promptCenter.actionTapped(prompt: prompt, actionId: action.id)
                        }
                        .buttonStyle(.borderedProminent)
                    } else {
                        Button(action.title) {
                            promptCenter.actionTapped(prompt: prompt, actionId: action.id)
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
        .padding(20)
        // Prevent the modal content from expanding to fill available height.
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct PromptModalOverlayView: View {
    @EnvironmentObject private var promptCenter: PromptCenter
    let prompt: Prompt

    var body: some View {
        GeometryReader { proxy in
            let cardWidth = min(520, max(280, proxy.size.width - 44))
            let center = CGPoint(x: proxy.size.width * 0.5, y: proxy.size.height * 0.5)

            ZStack {
                Color.black
                    .opacity(0.28)
                    .ignoresSafeArea()
                    .onTapGesture {
                        guard prompt.isClosable else { return }
                        promptCenter.dismissModal(reason: .close)
                    }

                PromptModalView(prompt: prompt)
                    .frame(width: cardWidth)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color(.systemBackground))
                            .shadow(color: .black.opacity(0.18), radius: 24, x: 0, y: 14)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(.black.opacity(0.06), lineWidth: 1)
                    )
                    .position(center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .transition(.opacity)
    }
}

private struct PromptHostOverlay: View {
    @EnvironmentObject private var promptCenter: PromptCenter
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled

    var body: some View {
        VStack(spacing: 0) {
            if let banner = promptCenter.banner {
                PromptBannerView(prompt: banner)
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .task(id: banner.id) {
                        let hasPrimary = (banner.primaryTitle?.isEmpty == false)
                        guard !hasPrimary else { return }

                        let voiceOverUI = UIAccessibility.isVoiceOverRunning
                        let voiceOver = voiceOverUI || voiceOverEnabled
 
                        let seconds = PromptTimings.bannerAutoDismissSeconds(
                            base: banner.autoDismissSeconds,
                            voiceOverEnabled: voiceOver
                        )

                        JPDebugPrint(
                            "PromptAutoDismissScheduled:\(banner.key) kind=banner seconds=\(seconds) voiceOver=\(voiceOver) voiceOver_ui=\(voiceOverUI) voiceOver_env=\(voiceOverEnabled)"
                        )

                        let ns = UInt64(max(0.0, seconds) * 1_000_000_000)
                        do {
                            try await Task.sleep(nanoseconds: ns)
                        } catch {
                            return
                        }

                        if promptCenter.banner?.id == banner.id {
                            await MainActor.run {
                                promptCenter.dismissBanner(reason: .auto)
                            }
                        }
                    }
            }

            Spacer(minLength: 0)

            if let toast = promptCenter.toast {
                PromptToastView(prompt: toast)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 18)
                    .allowsHitTesting(false)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .task(id: toast.id) {
                        let voiceOverUI = UIAccessibility.isVoiceOverRunning
                        let voiceOver = voiceOverUI || voiceOverEnabled

                        let seconds = PromptTimings.toastAutoDismissSeconds(
                            base: toast.autoDismissSeconds,
                            voiceOverEnabled: voiceOver
                        )

                        JPDebugPrint(
                            "PromptAutoDismissScheduled:\(toast.key) kind=toast seconds=\(seconds) voiceOver=\(voiceOver) voiceOver_ui=\(voiceOverUI) voiceOver_env=\(voiceOverEnabled)"
                        )

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
        .overlay {
            if let modal = promptCenter.modal {
                PromptModalOverlayView(prompt: modal)
            }
        }
        // Critical: ensure the overlay fills the host view. Without this, SwiftUI may
        // size the overlay to its content and the toast can effectively render off-screen.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .animation(.spring(response: 0.28, dampingFraction: 0.9), value: promptCenter.toast?.id)
        .animation(.spring(response: 0.28, dampingFraction: 0.9), value: promptCenter.banner?.id)
        .animation(.spring(response: 0.28, dampingFraction: 0.9), value: promptCenter.modal?.id)
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
