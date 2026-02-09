import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct CameraScreen: View {
    @EnvironmentObject private var promptCenter: PromptCenter
    @Environment(\.openURL) private var openURL

    @StateObject private var warmup = WarmupTracker()

    @StateObject private var cameraFrames = CameraFrameSource()
    @StateObject private var vision = VisionPipelineController()

    @State private var showingSettings = false
    @State private var showingPaywall = false
    @State private var showingInspiration = false
    @State private var showingDownReasons = false
    @State private var showingWrapSheet = false
    @State private var showingViewer = false
    @State private var showingPhotoViewer = false

    @State private var didShowCameraPermissionPreprompt = false
    @State private var cameraPermissionDeclined = false

    @State private var didShowWarmupFailModal = false
    @State private var didShowWorkset20LimitModalInThisFullState = false

    // If the user cancels the write_failed blocking modal, don't immediately re-show it
    // unless the write_failed count changes (new failures) or failures are cleared.
    @State private var dismissedWriteFailedCount: Int? = nil

    @State private var cameraAuth: CameraAuth = CameraAuthMapper.currentVideoAuth()
    @State private var lastPermissionBannerAuth: CameraAuth?

    @State private var worksetCount: Int = 0
    @State private var inFlightCount: Int = 0
    @State private var writeFailedCount: Int = 0
    @State private var albumAddFailedCount: Int = 0

    @State private var poseSpecValid: Bool = true

    @State private var filmstripItems: [SessionRepository.SessionItemSummary] = []
    @State private var selectedFilmstripItemId: String? = nil
    @State private var lastFilmstripCount: Int = 0

#if DEBUG
    private var visionDebugLine: String {
        "poseDetected=\(vision.poseDetected)  faceDetected=\(vision.faceDetected)"
    }
#endif

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("Camera")
                    .font(.title.bold())

                Text("MVP shell")
                    .foregroundStyle(.secondary)

                previewArea

                if !filmstripItems.isEmpty {
                    Filmstrip(
                        items: filmstripItems,
                        selectedItemId: $selectedFilmstripItemId,
                        onSelect: { item in
                            selectedFilmstripItemId = item.itemId
                            showingPhotoViewer = true
                            #if DEBUG
                            print("FilmstripSelect: item_id=\(item.itemId) shot_seq=\(item.shotSeq)")
                            #endif
                        },
                        onToggleLike: { item in
                            do {
                                let nextLiked = !item.liked
                                _ = try SessionRepository.shared.setLiked(itemId: item.itemId, liked: nextLiked)
                                NotificationCenter.default.post(name: CaptureEvents.sessionItemsChanged, object: nil)

                                Task {
                                    let r = await FavoriteSyncer.shared.syncFavoriteIfPossible(
                                        assetLocalIdentifier: item.assetId,
                                        isFavorite: nextLiked
                                    )
                                    if r == .failed {
                                        await MainActor.run { maybeShowFavoriteSyncFailedBanner() }
                                    }
                                }
                            } catch {
                                JPDebugPrint("FilmstripToggleLikeFAILED: item_id=\(item.itemId) error=\(error)")
                            }
                        }
                    )
                    .frame(height: 66)
                    .padding(.top, -6)
                }

                Button("Shutter") {
                    CaptureCoordinator.shared.shutterTapped()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!shutterGateResult.isEnabled || !poseSpecValid)

#if DEBUG
                Button("ExplainShutterDisabledReason") {
                    let r = shutterGateResult
                    if r.isEnabled {
                        print("ShutterEnabled")
                    } else {
                        print("ShutterDisabled:\(r.reason?.rawValue ?? "unknown")")
                    }
                    print("ShutterGateDebug: \(r.debugDescription)")
                }
                .buttonStyle(.bordered)
#endif

                if cameraPermissionDeclined {
                    Text("Camera permission not requested (declined).")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

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
        .task {
            checkPoseSpecOrBlock()
            configureCameraFrameHookIfNeeded()
            refreshCameraAuth()
            refreshWarmupState()
            updateCameraFrameSourceRunning()
            refreshSessionCounts()
            refreshFilmstrip()
            maybeShowCameraPermissionPreprompt()
            maybeShowPermissionBanner()
        }
#if canImport(UIKit)
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            refreshCameraAuth()
            refreshWarmupState()
            refreshSessionCounts()
            maybeShowPermissionBanner()
        }
#endif
        .onChange(of: cameraAuth) { _, _ in
            refreshWarmupState()
            maybeShowPermissionBanner()
            updateCameraFrameSourceRunning()
        }
        .onChange(of: poseSpecValid) { _, _ in
            updateCameraFrameSourceRunning()
        }
        .onChange(of: warmup.phase) { _, _ in
            refreshSessionCounts()
        }
        .onChange(of: showingSettings) { _, newValue in
            if !newValue {
                refreshSessionCounts()
#if DEBUG
                // Helps validate PoseSpec debug patches without relaunch.
                checkPoseSpecOrBlock()
#endif
            }
        }
        .onChange(of: showingPaywall) { _, newValue in
            if !newValue { refreshSessionCounts() }
        }
        .onChange(of: showingInspiration) { _, newValue in
            if !newValue { refreshSessionCounts() }
        }
        .onChange(of: showingDownReasons) { _, newValue in
            if !newValue { refreshSessionCounts() }
        }
        .onChange(of: showingViewer) { _, newValue in
            if !newValue { refreshSessionCounts() }
        }
        .onChange(of: showingPhotoViewer) { _, newValue in
            if !newValue { refreshSessionCounts() }
        }
        .onChange(of: warmup.phase) { _, newValue in
            guard newValue == .failed else { return }
            guard !didShowWarmupFailModal else { return }
            didShowWarmupFailModal = true
            promptCenter.show(makeWarmupFailedPrompt())
        }
        .onReceive(promptCenter.actionPublisher) { e in
            switch e.promptKey {
            case "camera_permission_preprompt":
                switch e.actionId {
                case "continue":
                    JPDebugPrint("CameraPermissionPreprompt: continue")
                    cameraPermissionDeclined = false

                    let current = CameraAuthMapper.currentVideoAuth()
                    guard current == .not_determined else {
                        JPDebugPrint("CameraPermissionRequestSkipped: current=\(current.rawValue)")
                        return
                    }

                    Task {
                        JPDebugPrint("CameraPermissionRequestStart")
                        let granted = await CameraAuthMapper.requestVideoAccess()
                        let after = CameraAuthMapper.currentVideoAuth()
                        JPDebugPrint("CameraPermissionRequestResult: granted=\(granted) after=\(after.rawValue)")

                        await MainActor.run {
                            cameraAuth = after
                            cameraPermissionDeclined = !granted
                            refreshWarmupState()
                        }
                    }
                case "cancel":
                    JPDebugPrint("CameraPermissionPreprompt: cancel")
                    cameraPermissionDeclined = true
                default:
                    break
                }
            case "camera_permission_denied":
                guard e.actionId == "go_settings" else { return }
#if canImport(UIKit)
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    openURL(url)
                }
#else
                #if DEBUG
                print("OpenSettingsUnavailable")
                #endif
#endif
            case "camera_permission_restricted":
                guard e.actionId == "understand" else { return }
                // No-op; the banner dismisses automatically on action.
                JPDebugPrint("CameraPermissionRestricted: understand")
            case "camera_warmup_failed":
                switch e.actionId {
                case "retry":
                    JPDebugPrint("CameraInitRetry")
                    didShowWarmupFailModal = false
                    refreshWarmupState(forceRestart: true)
                case "cancel":
                    JPDebugPrint("CameraWarmupFailed: cancel")
                case "go_settings":
#if canImport(UIKit)
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        openURL(url)
                    }
#else
                    #if DEBUG
                    print("OpenSettingsUnavailable")
                    #endif
#endif
                default:
                    break
                }
            case "workset_20_limit_modal":
                switch e.actionId {
                case "clear_unliked":
                    do {
                        let deleted = try SessionRepository.shared.clearUnlikedItemsForCurrentSession()
                        JPDebugPrint("WorksetClearUnliked: deleted=\(deleted)")
                        refreshSessionCounts()
                        promptCenter.show(
                            Prompt(
                                key: "workset_clear_unliked_done",
                                level: .L1,
                                surface: .cameraToastBottom,
                                priority: 10,
                                blocksShutter: false,
                                isClosable: false,
                                autoDismissSeconds: 2.0,
                                gate: .none,
                                title: nil,
                                message: "已清理未喜欢（\(deleted)）",
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
                                payload: ["deleted": .int(deleted)],
                                emittedAt: Date()
                            )
                        )
                    } catch {
                        JPDebugPrint("WorksetClearUnlikedFAILED: \(error)")
                    }
                case "go_wrap":
                    showingWrapSheet = true
                case "reset_session":
                    do {
                        let scene = (try SessionRepository.shared.loadCurrentSession()?.scene) ?? "cafe"
                        try SessionRepository.shared.clearCurrentSession(deleteData: true)
                        _ = try SessionRepository.shared.createNewSession(scene: scene)
                        didShowWorkset20LimitModalInThisFullState = false
                        refreshSessionCounts()
                        JPDebugPrint("SessionReset: ok")
                    } catch {
                        JPDebugPrint("SessionResetFAILED: \(error)")
                    }
                case "cancel":
                    // Cancel keeps shutter disabled while workset_count == 20 (SessionRuleGate enforces this).
                    break
                default:
                    break
                }
            case "workset_20_full_banner":
                guard e.actionId == "open_modal" else { break }
                promptCenter.show(makeWorkset20LimitModalPrompt())
            case "write_failed_block_modal":
                switch e.actionId {
                case "view":
                    showingViewer = true
                case "cancel":
                    dismissedWriteFailedCount = writeFailedCount
                default:
                    break
                }
            case "capture_failed_abnormal_modal":
                switch e.actionId {
                case "retry":
                    Task { await CaptureFailureTracker.shared.reset() }
                    refreshWarmupState(forceRestart: true)
                case "cancel":
                    Task { await CaptureFailureTracker.shared.reset() }
                default:
                    break
                }
            case "album_add_failed_banner":
                switch e.actionId {
                case "retry_album_add":
                    Task {
                        await retryAlbumAddFailedBatch()
                    }
                case "later":
                    break
                default:
                    break
                }
            case "favorite_sync_failed_banner":
                guard e.actionId == "go_settings" else { break }
#if canImport(UIKit)
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    openURL(url)
                }
#else
                #if DEBUG
                print("OpenSettingsUnavailable")
                #endif
#endif
            case "posespec_invalid_modal":
                guard e.actionId == "retry" else { break }
                checkPoseSpecOrBlock()
            case "posespec_version_mismatch_modal":
                guard e.actionId == "retry" else { break }
                checkPoseSpecOrBlock()
            case "posespec_binding_missing_modal":
                guard e.actionId == "retry" else { break }
                checkPoseSpecOrBlock()
            case "posespec_rois_missing_modal":
                guard e.actionId == "retry" else { break }
                checkPoseSpecOrBlock()
            default:
                break
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: CaptureEvents.captureFailed)) { _ in
            refreshSessionCounts()
            refreshFilmstrip()
            Task {
                let r = await CaptureFailureTracker.shared.recordFailure()
                await MainActor.run {
                    JPDebugPrint("CaptureFailedTracked: count_in_window=\(r.countInWindow) did_trigger=\(r.didTrigger)")
                    if r.didTrigger {
                        promptCenter.show(makeCaptureAbnormalModalPrompt(countInWindow: r.countInWindow))
                    } else {
                        promptCenter.show(makeCaptureFailedToast())
                    }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: CaptureEvents.writeFailed)) { _ in
            refreshSessionCounts()
            refreshFilmstrip()
        }
        .onReceive(NotificationCenter.default.publisher(for: CaptureEvents.albumAddFailed)) { _ in
            refreshSessionCounts()
            refreshFilmstrip()

            // M4.25: show once per session, only when a failure happens (not on app launch).
            do {
                let c = try SessionRepository.shared.countAlbumAddFailedItems()
                if c > 0 {
                    promptCenter.show(makeAlbumAddFailedBannerPrompt(count: c))
                }
            } catch {
                JPDebugPrint("AlbumAddFailedCountFAILED: \(error)")
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: CaptureEvents.sessionItemsChanged)) { _ in
            refreshFilmstrip()
        }
        .sheet(isPresented: $showingSettings) {
            SettingsSheet()
                .environment(\.promptHostInstalled, false)
        }
        .sheet(isPresented: $showingPaywall) {
            PaywallSheet()
                .environment(\.promptHostInstalled, false)
        }
        .sheet(isPresented: $showingInspiration) {
            InspirationSheet()
                .environment(\.promptHostInstalled, false)
        }
        .sheet(isPresented: $showingDownReasons) {
            DownReasonsSheet()
                .environment(\.promptHostInstalled, false)
        }
        .sheet(isPresented: $showingWrapSheet) {
            WrapScreen()
                .environment(\.promptHostInstalled, false)
        }
        .sheet(isPresented: $showingViewer) {
            ViewerScreen()
                .environment(\.promptHostInstalled, false)
        }
        .sheet(isPresented: $showingPhotoViewer) {
            ViewerContainer(items: filmstripItems, initialItemId: selectedFilmstripItemId)
                .environment(\.promptHostInstalled, false)
        }
    }

    private func maybeShowFavoriteSyncFailedBanner() {
        promptCenter.show(makeFavoriteSyncFailedBannerPrompt())
    }

    private func maybeShowCameraPermissionPreprompt() {
        guard !didShowCameraPermissionPreprompt else { return }
        guard cameraAuth == .not_determined else { return }

        didShowCameraPermissionPreprompt = true
        cameraPermissionDeclined = false
        promptCenter.show(makeCameraPermissionPreprompt())
    }

    private func checkPoseSpecOrBlock() {
        let expectedPrdVersion = PoseSpec.supportedVersion

#if DEBUG
        print(
            "PoseSpecCheckStart: armed_missing_alias=\(PoseSpecDebugSettings.debugIsMissingAliasArmed()) armed_missing_eye_roi=\(PoseSpecDebugSettings.debugIsMissingEyeROIArmed()) armed_wrong_prd=\(PoseSpecDebugSettings.debugIsWrongPrdArmed()) armed_broken=\(PoseSpecDebugSettings.debugIsBrokenPoseSpecArmed())"
        )
#endif
        do {
            let spec = try PoseSpecLoader.shared.loadPoseSpec()
            try PoseSpecValidator.validateRequiredFields(spec)
            try PoseSpecValidator.validatePrdVersion(spec)
            try PoseSpecValidator.validateBindingAliasesMinimalSet(spec)
            try PoseSpecValidator.validateRoisDictionary(spec)
            poseSpecValid = true
#if DEBUG
            print("PoseSpec Loaded & Validated")
#endif
        } catch {
            poseSpecValid = false
            if let k = promptCenter.modal?.key, k.hasPrefix("posespec_") {
                return
            }
            promptCenter.show(makePoseSpecInvalidPrompt(error: error, expectedPrdVersion: expectedPrdVersion))
        }
    }

    private func configureCameraFrameHookIfNeeded() {
        if cameraFrames.onFrame != nil { return }
        cameraFrames.onFrame = { pixelBuffer, orientation in
            vision.offer(pixelBuffer: pixelBuffer, orientation: orientation)
        }
    }

    private func updateCameraFrameSourceRunning() {
        if cameraAuth == .authorized, poseSpecValid {
            cameraFrames.start()
        } else {
            cameraFrames.stop()
        }
    }

    private func makePoseSpecInvalidPrompt(error: Error, expectedPrdVersion: String) -> Prompt {
        #if DEBUG
        print("PoseSpecInvalid: \(error)")
        #endif

        if case PoseSpecValidationError.prdVersionMismatch(let expected, let actual) = error {
            return Prompt(
                key: "posespec_version_mismatch_modal",
                level: .L3,
                surface: .cameraModalCenter,
                priority: 99,
                blocksShutter: true,
                isClosable: false,
                autoDismissSeconds: nil,
                gate: .stateOnly,
                title: "版本不一致",
                message: "PoseSpec 版本与 PRD 不一致，无法继续。\n\nexpected=\(expected)\nactual=\(actual)",
                primaryActionId: "retry",
                primaryTitle: "重试",
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
                payload: [
                    "expected": .string(expected),
                    "actual": .string(actual),
                ],
                emittedAt: Date()
            )
        }

        if case PoseSpecValidationError.bindingMissingAliases(let missing) = error {
            return Prompt(
                key: "posespec_binding_missing_modal",
                level: .L3,
                surface: .cameraModalCenter,
                priority: 99,
                blocksShutter: true,
                isClosable: false,
                autoDismissSeconds: nil,
                gate: .stateOnly,
                title: "binding 缺失",
                message: "PoseSpec 不完整：binding 缺失。\n\nmissing=\(missing.joined(separator: ", "))",
                primaryActionId: "retry",
                primaryTitle: "重试",
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
                payload: ["missing": .string(missing.joined(separator: ","))],
                emittedAt: Date()
            )
        }

        if case PoseSpecValidationError.bindingMissingBodyPointsSet = error {
            return Prompt(
                key: "posespec_binding_missing_modal",
                level: .L3,
                surface: .cameraModalCenter,
                priority: 99,
                blocksShutter: true,
                isClosable: false,
                autoDismissSeconds: nil,
                gate: .stateOnly,
                title: "binding 缺失",
                message: "PoseSpec 不完整：binding 缺失。\n\nmissing=bodyPoints",
                primaryActionId: "retry",
                primaryTitle: "重试",
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
                payload: ["missing": .string("bodyPoints")],
                emittedAt: Date()
            )
        }

        if case PoseSpecValidationError.bindingBodyPointsSetMismatch = error {
            return Prompt(
                key: "posespec_binding_missing_modal",
                level: .L3,
                surface: .cameraModalCenter,
                priority: 99,
                blocksShutter: true,
                isClosable: false,
                autoDismissSeconds: nil,
                gate: .stateOnly,
                title: "binding 缺失",
                message: "PoseSpec 不完整：binding 缺失。\n\nbodyPoints 定义不符合 PRD 4.4.2",
                primaryActionId: "retry",
                primaryTitle: "重试",
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
        }

        if case PoseSpecValidationError.roisMissing(let missing) = error {
            return Prompt(
                key: "posespec_rois_missing_modal",
                level: .L3,
                surface: .cameraModalCenter,
                priority: 99,
                blocksShutter: true,
                isClosable: false,
                autoDismissSeconds: nil,
                gate: .stateOnly,
                title: "rois 缺失",
                message: "PoseSpec 不完整：rois 缺失。\n\nmissing=\(missing.joined(separator: ", "))",
                primaryActionId: "retry",
                primaryTitle: "重试",
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
                payload: ["missing": .string(missing.joined(separator: ","))],
                emittedAt: Date()
            )
        }

        return Prompt(
            key: "posespec_invalid_modal",
            level: .L3,
            surface: .cameraModalCenter,
            priority: 99,
            blocksShutter: true,
            isClosable: false,
            autoDismissSeconds: nil,
            gate: .stateOnly,
            title: "PoseSpec 不完整",
            message: "PoseSpec 不完整，无法继续。\n\n\(error.localizedDescription)\n\nexpected_prdVersion=\(expectedPrdVersion)",
            primaryActionId: "retry",
            primaryTitle: "重试",
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
    }

    private func refreshCameraAuth() {
        cameraAuth = CameraAuthMapper.currentVideoAuth()
    }

    private func refreshWarmupState(forceRestart: Bool = false) {
        switch cameraAuth {
        case .authorized:
            let delay = WarmupDebugSettings.simulatedReadyDelaySec()
            if forceRestart {
                warmup.start(simulatedReadyDelaySec: delay)
            } else {
                warmup.startIfNeeded(simulatedReadyDelaySec: delay)
            }
        default:
            didShowWarmupFailModal = false
            warmup.stop()
        }
    }

    private func refreshSessionCounts() {
        do {
            let previous = worksetCount
            let counts = try SessionRepository.shared.currentWorksetCounter()
            let nextWorkset = counts?.worksetCount ?? 0
            worksetCount = nextWorkset
            inFlightCount = counts?.inFlightCount ?? 0
            writeFailedCount = try SessionRepository.shared.countWriteFailedItems()
            albumAddFailedCount = try SessionRepository.shared.countAlbumAddFailedItems()

            maybeShowWorkset15CountBanner(previousWorksetCount: previous, currentWorksetCount: nextWorkset)
            maybeShowWorkset20LimitModal(previousWorksetCount: previous, currentWorksetCount: nextWorkset)
            updateWorksetFullBanner(currentWorksetCount: nextWorkset)
            updateWriteFailedBlockModal(writeFailedCount: writeFailedCount)
        } catch {
            JPDebugPrint("RefreshSessionCountsFAILED: \(error)")
        }
    }

    private func refreshFilmstrip() {
        do {
            filmstripItems = try SessionRepository.shared.latestItemsForCurrentSession(limit: 30)
            if filmstripItems.count != lastFilmstripCount {
                lastFilmstripCount = filmstripItems.count
                JPDebugPrint("FilmstripRefreshed: count=\(filmstripItems.count)")
            }
            if selectedFilmstripItemId == nil {
                selectedFilmstripItemId = filmstripItems.first?.itemId
            }
        } catch {
            filmstripItems = []
            selectedFilmstripItemId = nil
            lastFilmstripCount = 0
            JPDebugPrint("RefreshFilmstripFAILED: \(error)")
        }
    }

    private func updateWriteFailedBlockModal(writeFailedCount: Int) {
        if writeFailedCount <= 0 {
            dismissedWriteFailedCount = nil
            return
        }

        // Don't keep preempting the same modal with itself.
        if promptCenter.modal?.key == "write_failed_block_modal" { return }

        // If another modal is visible, don't preempt it here.
        if let modal = promptCenter.modal, modal.key != "write_failed_block_modal" { return }

        if dismissedWriteFailedCount == writeFailedCount {
            return
        }

        let p = makeWriteFailedBlockModalPrompt()
        promptCenter.show(p)
    }

    private func maybeShowWorkset15CountBanner(previousWorksetCount: Int, currentWorksetCount: Int) {
        // M4.3: Only trigger on the 14 -> 15 transition; do not show if entering Camera with >= 15.
        guard previousWorksetCount == 14, currentWorksetCount == 15 else { return }
        promptCenter.show(makeWorkset15CountBannerPrompt())
    }

    private func maybeShowWorkset20LimitModal(previousWorksetCount: Int, currentWorksetCount: Int) {
        if currentWorksetCount < 20 {
            didShowWorkset20LimitModalInThisFullState = false
            return
        }

        // Defensive: treat 20+ as "full".
        guard currentWorksetCount >= 20 else { return }
        guard !didShowWorkset20LimitModalInThisFullState else { return }

        let p = makeWorkset20LimitModalPrompt()
        promptCenter.show(p)
        if promptCenter.modal?.key == p.key {
            didShowWorkset20LimitModalInThisFullState = true
        }
    }

    private func updateWorksetFullBanner(currentWorksetCount: Int) {
        // If the user cancels the 20-limit modal, keep an actionable banner so they can
        // reopen it and resolve the full-workset state.
        if currentWorksetCount < 20 {
            if let banner = promptCenter.banner, banner.key == "workset_20_full_banner" {
                promptCenter.dismissBanner(reason: .auto)
            }
            return
        }

        // If the blocking modal is visible, don't also show the banner.
        if promptCenter.modal?.key == "workset_20_limit_modal" {
            if let banner = promptCenter.banner, banner.key == "workset_20_full_banner" {
                promptCenter.dismissBanner(reason: .auto)
            }
            return
        }

        promptCenter.show(makeWorkset20FullBannerPrompt())
    }

    private var shutterGateResult: SessionRuleGate.Result {
        SessionRuleGate.evaluate(
            .init(
                cameraAuth: cameraAuth,
                warmupPhase: warmup.phase,
                worksetCount: worksetCount,
                inFlightCount: inFlightCount,
                writeFailedCount: writeFailedCount
            )
        )
    }

    private var previewArea: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(.systemGray6), Color(.systemGray5)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(.black.opacity(0.06), lineWidth: 1)
                )

            if cameraAuth == .authorized, cameraFrames.state != .failed {
                CameraPreviewView(
                    session: cameraFrames.session,
                    debugROIs: ROIComputer.compute(face: vision.lastFace)
                )
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }

            VStack(spacing: 8) {
                switch cameraAuth {
                case .authorized:
                    if cameraFrames.state == .failed {
                        Text("No camera preview")
                            .font(.headline)
                        Text("Camera init failed")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Camera preview")
                            .font(.headline)
                        #if DEBUG
                        Text(visionDebugLine)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        #endif
                    }
                case .denied:
                    Text("No camera preview")
                        .font(.headline)
                    Text("Permission denied")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                case .restricted:
                    Text("No camera preview")
                        .font(.headline)
                    Text("Restricted by system")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                case .not_determined:
                    Text("Camera permission")
                        .font(.headline)
                    Text("Not requested")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()

            if cameraAuth == .authorized, warmup.phase != .ready {
                warmupOverlay
                    .transition(.opacity)
            }
        }
        .frame(height: 360)
    }

    private var warmupOverlay: some View {
        let message: String
        switch warmup.phase {
        case .warming:
            message = "相机准备中…"
        case .upgraded:
            message = "相机准备中…（可能需要几秒）"
        case .failed:
            message = "相机初始化失败"
        case .idle, .ready:
            message = ""
        }

        return VStack(spacing: 10) {
            ProgressView()
                .tint(.white)
            Text(message)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.black.opacity(0.72))
        )
        .padding(16)
    }

    private func makeWarmupFailedPrompt() -> Prompt {
        let reason = currentWarmupFailureReason()
        let message = "\(reason.explanationText)。相机准备超时（>8s）。"
        return Prompt(
            key: "camera_warmup_failed",
            level: .L3,
            surface: .cameraModalCenter,
            priority: 95,
            blocksShutter: true,
            isClosable: false,
            autoDismissSeconds: nil,
            gate: .stateOnly,
            title: "相机初始化失败",
            message: message,
            primaryActionId: "retry",
            primaryTitle: "重试",
            secondaryActionId: "cancel",
            secondaryTitle: "取消",
            tertiaryActionId: (reason == .permission_denied) ? "go_settings" : nil,
            tertiaryTitle: (reason == .permission_denied) ? "去设置" : nil,
            throttle: .init(
                perKeyMinIntervalSec: 0,
                globalWindowSec: 0,
                globalMaxCountInWindow: 0,
                suppressAfterDismissSec: 0
            ),
            payload: [:],
            emittedAt: Date()
        )
    }

    private func currentWarmupFailureReason() -> CameraInitFailureReason {
        if let simulated = CameraInitFailureDebugSettings.simulatedFailureReason() {
            return simulated
        }

        if cameraAuth == .denied || cameraAuth == .restricted {
            return .permission_denied
        }

        return .unknown
    }

    private func maybeShowPermissionBanner() {
        switch cameraAuth {
        case .denied, .restricted:
            guard lastPermissionBannerAuth != cameraAuth else { return }
            lastPermissionBannerAuth = cameraAuth
            switch cameraAuth {
            case .denied:
                promptCenter.show(makeDeniedPermissionBanner())
            case .restricted:
                promptCenter.show(makeRestrictedPermissionBanner())
            default:
                break
            }
        default:
            lastPermissionBannerAuth = nil
            if let banner = promptCenter.banner,
               banner.key == "camera_permission_denied" || banner.key == "camera_permission_restricted"
            {
                promptCenter.dismissBanner(reason: .auto)
            }
        }
    }

    private func makeDeniedPermissionBanner() -> Prompt {
        Prompt(
            key: "camera_permission_denied",
            level: .L2,
            surface: .cameraBannerTop,
            priority: 80,
            blocksShutter: true,
            isClosable: false,
            autoDismissSeconds: nil,
            gate: .stateOnly,
            title: nil,
            message: "未获得相机权限，无法拍照",
            primaryActionId: "go_settings",
            primaryTitle: "去设置",
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
    }

    private func makeRestrictedPermissionBanner() -> Prompt {
        Prompt(
            key: "camera_permission_restricted",
            level: .L2,
            surface: .cameraBannerTop,
            priority: 80,
            blocksShutter: true,
            isClosable: false,
            autoDismissSeconds: nil,
            gate: .stateOnly,
            title: nil,
            message: "相机受系统限制，无法使用",
            primaryActionId: "understand",
            primaryTitle: "了解",
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
    }

    private func makeCameraPermissionPreprompt() -> Prompt {
        Prompt(
            key: "camera_permission_preprompt",
            level: .L3,
            surface: .cameraModalCenter,
            priority: 90,
            blocksShutter: true,
            isClosable: false,
            autoDismissSeconds: nil,
            gate: .stateOnly,
            title: "需要相机权限",
            message: "Just Photo 需要相机权限才能拍照",
            primaryActionId: "continue",
            primaryTitle: "继续",
            secondaryActionId: "cancel",
            secondaryTitle: "取消",
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
    }

    private func makeWorkset15CountBannerPrompt() -> Prompt {
        Prompt(
            key: "workset_15_count_banner",
            level: .L2,
            surface: .cameraBannerTop,
            priority: 40,
            blocksShutter: false,
            isClosable: true,
            autoDismissSeconds: nil,
            gate: .sessionOnce,
            title: nil,
            message: "已拍到 15 张。可以去查看并挑选喜欢的照片。",
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
            payload: [
                "workset_count": .int(15),
            ],
            emittedAt: Date()
        )
    }

    private func makeWorkset20LimitModalPrompt() -> Prompt {
        Prompt(
            key: "workset_20_limit_modal",
            level: .L3,
            surface: .cameraModalCenter,
            priority: 70,
            blocksShutter: true,
            isClosable: false,
            autoDismissSeconds: nil,
            gate: .stateOnly,
            title: "已拍满 20 张",
            message: "已拍满 20 张，请先挑选或清理。",
            primaryActionId: "clear_unliked",
            primaryTitle: "清理未喜欢",
            secondaryActionId: "go_wrap",
            secondaryTitle: "去拼图",
            tertiaryActionId: "reset_session",
            tertiaryTitle: "重置会话",
            quaternaryActionId: "cancel",
            quaternaryTitle: "取消",
            throttle: .init(
                perKeyMinIntervalSec: 0,
                globalWindowSec: 0,
                globalMaxCountInWindow: 0,
                suppressAfterDismissSec: 0
            ),
            payload: [
                "workset_count": .int(20),
            ],
            emittedAt: Date()
        )
    }

    private func makeWorkset20FullBannerPrompt() -> Prompt {
        Prompt(
            key: "workset_20_full_banner",
            level: .L2,
            surface: .cameraBannerTop,
            priority: 60,
            blocksShutter: true,
            isClosable: false,
            autoDismissSeconds: nil,
            gate: .stateOnly,
            title: nil,
            message: "已拍满 20 张，请先挑选或清理",
            primaryActionId: "open_modal",
            primaryTitle: "处理",
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
            payload: [
                "workset_count": .int(20),
            ],
            emittedAt: Date()
        )
    }

    private func makeCaptureFailedToast() -> Prompt {
        Prompt(
            key: "capture_failed_toast",
            level: .L1,
            surface: .cameraToastBottom,
            priority: 20,
            blocksShutter: false,
            isClosable: false,
            autoDismissSeconds: 2.0,
            gate: .none,
            title: nil,
            message: "没拍到",
            primaryActionId: nil,
            primaryTitle: nil,
            secondaryActionId: nil,
            secondaryTitle: nil,
            tertiaryActionId: nil,
            tertiaryTitle: nil,
            throttle: .init(
                perKeyMinIntervalSec: 10,
                globalWindowSec: 0,
                globalMaxCountInWindow: 0,
                suppressAfterDismissSec: 0
            ),
            payload: [:],
            emittedAt: Date()
        )
    }

    private func makeCaptureAbnormalModalPrompt(countInWindow: Int) -> Prompt {
        Prompt(
            key: "capture_failed_abnormal_modal",
            level: .L3,
            surface: .cameraModalCenter,
            priority: 88,
            blocksShutter: false,
            isClosable: false,
            autoDismissSeconds: nil,
            gate: .stateOnly,
            title: "相机异常",
            message: "连续 \(countInWindow) 次没拍到。建议重试相机初始化，或稍后再试。",
            primaryActionId: "retry",
            primaryTitle: "重试",
            secondaryActionId: "cancel",
            secondaryTitle: "取消",
            tertiaryActionId: nil,
            tertiaryTitle: nil,
            throttle: .init(
                perKeyMinIntervalSec: 0,
                globalWindowSec: 0,
                globalMaxCountInWindow: 0,
                suppressAfterDismissSec: 30
            ),
            payload: ["count": .int(countInWindow)],
            emittedAt: Date()
        )
    }

    private func makeAlbumAddFailedBannerPrompt(count: Int) -> Prompt {
        Prompt(
            key: "album_add_failed_banner",
            level: .L2,
            surface: .cameraBannerTop,
            priority: 60,
            blocksShutter: false,
            isClosable: false,
            autoDismissSeconds: nil,
            gate: .sessionOnce,
            title: nil,
            message: "部分照片未归档到 Just Photo 相册",
            primaryActionId: "retry_album_add",
            primaryTitle: "修复",
            secondaryActionId: "later",
            secondaryTitle: "稍后",
            tertiaryActionId: nil,
            tertiaryTitle: nil,
            throttle: .init(
                perKeyMinIntervalSec: 10,
                globalWindowSec: 20,
                globalMaxCountInWindow: 2,
                suppressAfterDismissSec: 60
            ),
            payload: ["album_add_failed_count": .int(count)],
            emittedAt: Date()
        )
    }

    private func makeFavoriteSyncFailedBannerPrompt() -> Prompt {
        Prompt(
            key: "favorite_sync_failed_banner",
            level: .L2,
            surface: .cameraBannerTop,
            priority: 58,
            blocksShutter: false,
            isClosable: true,
            autoDismissSeconds: nil,
            gate: .sessionOnce,
            title: nil,
            message: "已在 App 内标记喜欢，但同步到系统收藏失败。你仍可继续拍摄。",
            primaryActionId: "go_settings",
            primaryTitle: "去设置",
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
    }

    private func retryAlbumAddFailedBatch() async {
        let items: [SessionRepository.SessionItemSummary] = await MainActor.run {
            (try? SessionRepository.shared.albumAddFailedItemsForCurrentSession()) ?? []
        }

        await AlbumAddRetryScheduler.shared.cancel(itemIds: items.map { $0.itemId })

        let total = items.count
        if total == 0 {
            await MainActor.run {
                refreshSessionCounts()
                promptCenter.show(makeAlbumRetryToast(key: "album_retry_empty", message: "暂无需要修复的照片"))
            }
            return
        }

        var ok = 0
        var failed = 0
        var skipped = 0

        for item in items {
            guard let assetId = item.assetId, !assetId.isEmpty else {
                skipped += 1
                continue
            }

            do {
                _ = try await AlbumArchiver.shared.archive(assetLocalIdentifier: assetId)
                ok += 1
                await MainActor.run {
                    do {
                        try SessionRepository.shared.markAlbumAddSuccess(itemId: item.itemId)
                    } catch {
                        JPDebugPrint("AlbumRetryMarkSuccessFAILED: \(error)")
                    }
                }
            } catch {
                if case AlbumArchiverError.assetNotFound = error {
                    // Phantom/missing asset: heal locally and exclude from results.
                    if let report = await PhantomAssetHealer.shared.healIfNeeded(itemId: item.itemId, assetId: assetId, source: "album_manual_retry") {
                        skipped += 1
                        JPDebugPrint("AlbumRetryHealedPhantom: item_id=\(item.itemId) action=\(report.healAction.rawValue)")
                        continue
                    }
                }
                failed += 1
                JPDebugPrint("AlbumRetryFAILED: item_id=\(item.itemId) asset_id=\(assetId) error=\(error)")
            }
        }

        await MainActor.run {
            refreshSessionCounts()

            let msg: String
            if failed == 0 {
                msg = "修复完成：\(ok)/\(total)"
            } else {
                msg = "修复结果：\(ok)/\(total)（失败\(failed)）"
            }
            let payload: [String: PromptPayloadValue] = [
                "total": .int(total),
                "ok": .int(ok),
                "failed": .int(failed),
                "skipped": .int(skipped),
            ]
            promptCenter.show(makeAlbumRetryToast(key: "album_retry_result", message: msg, payload: payload))
        }
    }

    private func makeAlbumRetryToast(key: String, message: String, payload: [String: PromptPayloadValue] = [:]) -> Prompt {
        Prompt(
            key: key,
            level: .L1,
            surface: .cameraToastBottom,
            priority: 6,
            blocksShutter: false,
            isClosable: false,
            autoDismissSeconds: 2.0,
            gate: .none,
            title: nil,
            message: message,
            primaryActionId: nil,
            primaryTitle: nil,
            secondaryActionId: nil,
            secondaryTitle: nil,
            tertiaryActionId: nil,
            tertiaryTitle: nil,
            throttle: .init(
                perKeyMinIntervalSec: 2,
                globalWindowSec: 0,
                globalMaxCountInWindow: 0,
                suppressAfterDismissSec: 0
            ),
            payload: payload,
            emittedAt: Date()
        )
    }

    private func makeWriteFailedBlockModalPrompt() -> Prompt {
        Prompt(
            key: "write_failed_block_modal",
            level: .L3,
            surface: .cameraModalCenter,
            priority: 92,
            blocksShutter: true,
            isClosable: false,
            autoDismissSeconds: nil,
            gate: .stateOnly,
            title: "有照片未保存",
            message: "有照片未保存，请先处理。",
            primaryActionId: "view",
            primaryTitle: "查看并处理",
            secondaryActionId: "cancel",
            secondaryTitle: "取消",
            tertiaryActionId: nil,
            tertiaryTitle: nil,
            throttle: .init(
                perKeyMinIntervalSec: 0,
                globalWindowSec: 0,
                globalMaxCountInWindow: 0,
                suppressAfterDismissSec: 0
            ),
            payload: [
                "write_failed_count": .int(writeFailedCount),
            ],
            emittedAt: Date()
        )
    }
}

#Preview {
    CameraScreen()
        .environmentObject(PromptCenter())
}
