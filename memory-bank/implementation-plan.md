# Implementation Plan (Atomic++ / Verification-First) — Just Photo MVP (iOS 16+)

Scope: MVP only. Follow `memory-bank/product-requirement.md v1.1.4` + `memory-bank/PoseSpec.json prdVersion=v1.1.4`. Local-only data and logs. No account. No photo upload. No remote analytics SDK.

Tech stack binding (Glue Coding):
- Apple APIs: Swift, SwiftUI + UIKit bridge, AVFoundation, Vision, PhotoKit, Network.framework (NWPathMonitor), On-Demand Resources, StoreKit 2, OSLog
- Third-party: GRDB (SQLite)

Conventions used in this plan:
- “Console verify” means Xcode console output (developer-only).
- “Diagnostics verify” means exported JSON Lines log (PRD Appendix A.13), searched by `event`.

---

## Milestone 0 — Project Skeleton (Runs + Navigates + Debug Hooks)

M0.1 Create Xcode project (iOS 16+, Swift)
- Do: Create project, set Deployment Target iOS 16, set signing for a real device.
- Verify: Run on device; app shows a placeholder Camera screen; no crash.

M0.2 Create top-level folder/groups in Xcode
- Do: Add groups/folders: `App/`, `Features/`, `Infrastructure/`, `Resources/`.
- Verify: Build succeeds; no missing file errors.

M0.3 Create empty screen files (no logic)
- Do: Create files for Camera, Viewer, Settings, Paywall, Inspiration, Wrap, DownReasons screens/sheets (shell UI only).
- Verify: Launch app; Camera can open each sheet/page and dismiss back.

M0.4 Add Info.plist permission strings
- Do: Add camera + photo library (read/write) usage descriptions (support Limited).
- Verify: First time triggering camera/photos prompts shows system dialog with correct text.

M0.5 Add Debug Tools entry (Debug build only)
- Do: Add a Debug section in Settings that appears only in Debug configuration.
- Verify: Debug build shows Debug section; Release build does not.

M0.6 Add “DebugToolsPing” button
- Do: Button prints a fixed console line `DebugToolsPing`.
- Verify: Tap button; console prints exactly `DebugToolsPing`.

---

## Milestone 1 — Diagnostics Log (A.13) + GRDB + SessionStore Base (Recoverable)

### 1A. Diagnostics Log (PRD A.13)

M1.1 Create diagnostics module files
- Do: Create `Infrastructure/Diagnostics/` files for: event model, logger, rotation manager, exporter.
- Verify: Build succeeds; DebugToolsPing still works.

M1.2 Define mandatory JSONL record fields (A.13)
- Do: Ensure every line includes: `ts_ms`, `session_id`, `event`, `scene`, `payload`.
- Verify: Add Debug button “WriteTestDiagnostic”; export logs; open file; confirm these keys exist on the last line.

M1.3 Implement “append one JSON line”
- Do: Implement single entrypoint to append one JSON object per line to the current log.
- Verify: Tap “WriteTestDiagnostic”; console prints `DiagnosticAppended`; exported log file grows by 1 line.

M1.4 Implement log file location and naming
- Do: Store logs in app sandbox; define stable directory + rolling file naming.
- Verify: Tap “PrintDiagnosticsPath”; console prints a real sandbox path; exporting includes files from that path.

M1.5 Implement rotation by total size (50MB)
- Do: Enforce total log directory size cap = 50MB; delete oldest first.
- Verify: Tap “SpamDiagnostics”; console prints `RotationBySizeTriggered`; total size stops growing beyond cap.

M1.6 Implement rotation by age (30 days)
- Do: Delete logs older than 30 days.
- Verify: Tap “CreateFakeOldLogs” then “RunRotationNow”; console prints deleted filenames.

M1.7 Implement Settings “Export Diagnostics Logs”
- Do: Add Settings button that shares all current log files via system share sheet.
- Verify: Tap export; share sheet appears; save to Files; files open and contain JSON lines.

M1.8 Add A.13 required events (just the ability to write them)
- Do: Add logger helpers for events: `withref_match_state`, `withref_fallback`, `photo_write_verification`, `phantom_asset_detected`, `odr_auto_retry`.
- Verify: Debug buttons emit each event once; exported logs contain all 5 `event` values.

### 1B. GRDB (third-party) + DB bootstrap

M1.9 Add GRDB via Swift Package Manager
- Do: Add GRDB dependency.
- Verify: Build succeeds; on app launch console prints `GRDBReady`.

M1.10 Create DB bootstrap files
- Do: Create `Infrastructure/Database/` files: paths, migrator, DB access wrapper.
- Verify: Tap “PrintDBPath”; console prints a path under Application Support.

M1.11 Create DB file on first launch
- Do: Ensure DB file is created/opened.
- Verify: After launch, DB file exists at printed path; restarting app still opens it.

M1.12 Add migration framework (v1)
- Do: Add migration runner with schema versioning.
- Verify: First run prints `DBMigrated:v1`; second run prints `DBMigrationsUpToDate`.

### 1C. SessionStore (PRD Appendix B) minimal persistence + TTL

M1.13 Create tables (sessions)
- Do: Create `sessions` table with required fields (sessionId, createdAt, lastActiveAt, scene, flags blob/json).
- Verify: Debug “DBCheckTables” prints `sessions=true`.

M1.14 Create tables (session_items)
- Do: Create `session_items` table with required fields (itemId, sessionId, shotSeq, createdAt, state, liked, assetId, pendingFileRelPath, thumbCacheRelPath, lastErrorAt).
- Verify: DBCheckTables prints `session_items=true`.

M1.15 Create tables (ref_items)
- Do: Create `ref_items` table (refId, sessionId, createdAt, assetId, selected, targetOutputs).
- Verify: DBCheckTables prints `ref_items=true`.

M1.16 Create tables (local_stats)
- Do: Create `local_stats` key/value table for local-only counters.
- Verify: DBCheckTables prints `local_stats=true`.

M1.17 Create SessionRepository (single read/write gateway)
- Do: Create repository that can load/save/clear current session and its related items.
- Verify: Tap “CreateNewSession”; console prints `SessionCreated:<id>`; restart app; “PrintSessionId” shows same id.

M1.18 Implement session TTL = 12h (B.3.4)
- Do: On app start/resume, if now-lastActiveAt > 12h, clear old session and create new.
- Verify: Tap “SetSessionOldLastActive”; restart app; sessionId changes; workset is empty.

M1.19 Implement immediate flush on critical moments (B.3.1)
- Do: On app backgrounding and on `write_failed`, force immediate DB flush (no debounce).
- Verify: Trigger write_failed, immediately kill app, restart; failed item still exists.

---

## Milestone 2 — Prompt System (L1/L2/L3 + Mutual Exclusion + VoiceOver Timings + Local prompt logs)

M2.1 Create Prompt model file
- Do: Create model fields aligned with PRD: key/level/surface/priority/blocksShutter/title/message/actions/payload.
- Verify: Debug “ShowTestL3” shows a modal with title/message/buttons.

M2.2 Create PromptCenter (single controller)
- Do: Create a central controller for showing/dismissing/promoting prompts.
- Verify: Tap “ShowTestL3A” then “ShowTestL3B”; only B remains visible; console prints `PromptPreempted:A->B`.

M2.3 Implement L1 Toast slot
- Do: Add UI slot for L1 toast with auto-dismiss timing.
- Verify: Tap “ShowTestToast”; toast appears then disappears automatically.

M2.4 Implement L2 Banner slot
- Do: Add UI slot for banner; supports optional primary button; closable.
- Verify: Tap “ShowTestBannerWithButton”; banner stays until button/close; tap button prints `BannerPrimaryTapped`.

M2.5 Implement L3 Modal slot
- Do: Add global modal presentation for L3; non-auto-dismiss.
- Verify: Tap “ShowTestL3”; modal stays until user taps a button.

M2.6 Implement VoiceOver timing switch (VOICEOVER_*)
- Do: Detect VoiceOver enabled; use VOICEOVER durations for toast/banner.
- Verify: Enable VoiceOver in iOS; trigger toast/banner; observe longer duration; console prints `VoiceOver=true`.

M2.7 Log prompt events locally (A.12)
- Do: On prompt show/dismiss/action, write diagnostics events `prompt_shown`, `prompt_dismissed`, `prompt_action_tapped`.
- Verify: Trigger a prompt and tap action; exported logs include these events with required fields.

---

## Milestone 3 — Camera Permission State Machine + Warmup Timeouts (P0)

M3.1 Create CameraAuth module (AVAuthorizationStatus mapping)
- Do: Implement status mapping to PRD enum: not_determined/authorized/denied/restricted.
- Verify: Debug “PrintCameraAuth” prints correct state under each system setting.

M3.2 Implement not_determined pre-prompt (PRD 4.1.2)
- Do: On first Camera entry when not_determined, show L3 pre-prompt with Continue/Cancel.
- Verify: Fresh install -> open Camera -> pre-prompt appears; Cancel returns away from Camera.

M3.3 Wire Continue to trigger system camera permission dialog
- Do: Only after Continue, request camera permission.
- Verify: Tap Continue; iOS permission dialog appears.

M3.4 Implement denied/restricted UI
- Do: Replace preview with placeholder; shutter disabled; show L2 banner with correct action (Go Settings vs Understand).
- Verify: Deny permission; Camera shows banner and disabled shutter; Go Settings opens iOS Settings.

M3.5 Create WarmupState tracker (3s upgrade, 8s fail)
- Do: Start timer when entering camera init; upgrade message at 3s; hard-fail prompt at 8s.
- Verify: Debug “SimulateWarmupDelay=4s” shows upgraded message after 3s.

M3.6 Define CameraInitFailureReason enum and mapping
- Do: Support reasons in PRD: permission_denied/camera_in_use/hardware_unavailable/unknown; map to user text.
- Verify: Debug select reason; fail modal message includes the chosen reason explanation.

M3.7 Implement “Retry camera init”
- Do: Retry button resets warmup state and restarts init pipeline.
- Verify: On fail modal, tap Retry; warmup restarts; console prints `CameraInitRetry`.

---

## Milestone 4 — Capture + Save State Machine (P0 Data Safety) + Pending Recovery

(Uses AVFoundation + PhotoKit; must not block preview; must satisfy PRD 6.1 + Appendix B.)

### 4A. Rules & Counters

M4.1 Create WorksetCounter utility
- Do: Implement workset_count and in_flight_count per PRD definitions.
- Verify: Debug “PrintCounts” matches UI item count and in-flight behavior.

M4.2 Create SessionRuleGate module (single source for shutter enable)
- Do: Centralize gates: write_failed global block, in_flight<=2, workset<20, warmup complete, permission authorized.
- Verify: Debug “ExplainShutterDisabledReason” outputs one clear reason matching UI state.

M4.3 Implement 15-count banner gate (14->15, sessionOnce)
- Do: Store a per-session flag (in DB) so it triggers only once per session.
- Verify: Shoot to 15 -> banner appears once; continuing to 16+ does not show again; reset session re-enables.

M4.4 Implement 20-limit modal + shutter disabled persists after cancel
- Do: On reaching 20, show L3 with 4 actions; cancel keeps shutter disabled until count < 20.
- Verify: Reach 20 -> modal; tap cancel -> shutter still disabled; clear/reset -> shutter enabled.

### 4B. Capture pipeline (optimistic -> pending file -> PhotoKit write)

M4.5 Create CaptureCoordinator file (single pipeline owner)
- Do: Create a coordinator responsible for the whole capture/save pipeline and state transitions.
- Verify: Tap shutter; console prints `ShutterTapReceived` and `PipelineStarted`.

M4.6 Create SessionItemState definition aligned with PRD
- Do: Enumerate states: captured_preview/writing/write_success/write_failed/album_add_success/album_add_failed/thumb_ready/thumb_failed.
- Verify: Debug “ListSessionItemStates” prints all states; QA can confirm names match PRD.

M4.7 Implement shutter tap gate checks (no capture when blocked)
- Do: If blocked (write_failed present, in_flight==2, workset==20), do not start capture and do not create new item.
- Verify: Force blocked state; tap shutter; no new filmstrip item; console prints `CaptureSkipped:blocked`.

M4.8 Create optimistic item immediately
- Do: Insert `captured_preview` item at workset head; assign stable itemId and monotonic shotSeq; flush to DB quickly.
- Verify: Tap shutter; filmstrip item appears instantly; kill app immediately; restart -> item still exists.

M4.9 Create PendingFileStore module (Application Support/pending)
- Do: Implement atomic write (tmp then rename) and deletion.
- Verify: Debug “WriteDummyPending”; console prints `PendingFileWritten`; file exists in pending directory.

M4.10 Write photo data to pending within 2s or convert to capture_failed
- Do: Start a 2s timer after optimistic insert; if no photo data arrives by then, remove item and emit capture_failed.
- Verify: Debug “SimulateNoPhotoData”; after 2s item disappears and a capture_failed toast shows.

M4.11 Start PhotoKit write only after pending file exists
- Do: Transition to `writing` only after pending file write succeeds; then call PhotoKit save.
- Verify: Normal shot shows state transitions in Debug overlay: captured_preview -> writing -> write_success.

### 4C. Asset Fetch Verification Retry (v1.1.4)

M4.12 Implement immediate fetch verification after write_success
- Do: After PhotoKit returns assetId, attempt to fetch it immediately.
- Verify: Export logs include `photo_write_verification` with `first_fetch_ms`.

M4.13 Implement 500ms×1 retry if first fetch fails
- Do: If fetch is nil/empty, retry once after 500ms; record retry_used and verified_within_2s.
- Verify: Debug “ForceFirstFetchNilThenSuccess”; exported logs show `retry_used=true`, `retry_delay_ms=500`.

### 4D. write_failed global block (A.11) + Viewer handling

M4.14 Define write_failed reasons enum list (PRD A.10)
- Do: Create a reason enum matching PRD; ensure UI message follows parentheses rule.
- Verify: Force each reason; Viewer top bar text matches “未保存到系统相册（原因）” or no parentheses when empty.

M4.15 On write_failed: force immediate DB flush
- Do: Ensure write_failed state is persisted immediately (no debounce).
- Verify: Force write_failed, kill app, relaunch; failed item is still in workset.

M4.16 On write_failed: block shutter and show L3 on Camera
- Do: Show L3 “有照片未保存，请先处理” with actions “查看并处理/取消”; cancel does not unblock.
- Verify: Tap cancel; shutter still disabled; banner/modal rules match PRD.

M4.17 Implement Viewer “retry save”
- Do: In Viewer for failed item, tapping retry re-runs PhotoKit write using pending file, then runs verification.
- Verify: Force a recoverable failure; retry succeeds; item becomes write_success; shutter unblocks.

M4.18 Implement Viewer “abandon item”
- Do: Remove item from workset and DB; delete pending file; do not touch system Photos library.
- Verify: Tap abandon; item disappears; pending file removed; shutter unblocks.

### 4E. capture_failed counter window (30s / 3 times -> L3)

M4.19 Create CaptureFailureTracker module
- Do: Track capture_failed occurrences in a rolling 30s window.
- Verify: Trigger 3 failures within 30s; third triggers L3 “相机异常”.

### 4F. Thumbnails: thumb_failed + self-heal + rebuild

M4.20 Create ThumbnailPipeline module
- Do: Centralize thumbnail generation requests and timing.
- Verify: Tap shutter; console prints `ThumbPipelineStarted:itemId=...`.

M4.21 Implement 5s threshold to mark thumb_failed
- Do: If real thumbnail not ready within 5s from captured_preview, mark thumb_failed and show `!`.
- Verify: Debug “DelayThumbnail=6s”; filmstrip shows `!` at ~5s.

M4.22 Implement late self-heal (thumb_failed -> thumb_ready)
- Do: When thumbnail finally arrives, automatically clear `!` and mark thumb_ready.
- Verify: After delayed thumbnail arrives, `!` disappears without user action.

M4.23 Implement 30s permanent failure + “Rebuild thumbnail”
- Do: If still missing at 30s, show Viewer action “重建缩略”.
- Verify: Debug “DelayThumbnail=35s”; Viewer shows “重建缩略”; tapping prints `ThumbRebuildRequested`.

### 4G. Album archiving: album_add_failed non-blocking + retry policy

M4.24 Create AlbumArchiver module (PhotoKit album add)
- Do: Ensure “Just Photo” album exists; add assets to it; handle failures.
- Verify: After successful archiving, system Photos shows “Just Photo” album with new photo.

M4.25 Implement album_add_failed state + first-session banner
- Do: If add-to-album fails, set album_add_failed and show L2 banner once per session with “修复/稍后”.
- Verify: Force archiving failure; banner shows once; choose “稍后”; subsequent failures don’t auto-banner.

M4.26 Implement “修复” bulk retry
- Do: Retry all album_add_failed items in current session once.
- Verify: Tap “修复”; console prints `AlbumRetryBatchStarted`; on success banner disappears.

M4.27 Implement automatic retry backoff (1s/3s/10s, max 3)
- Do: Per item, auto retry up to 3 times with specified delays.
- Verify: Force first 2 retries fail and 3rd succeed; observe console timestamps approximate backoff schedule.

M4.28 Implement “retry once on next launch”
- Do: On app launch, if any album_add_failed exists, attempt one silent retry; show banner only if still failing.
- Verify: Force album_add_failed, kill app, relaunch; console prints `AlbumRetryOnLaunchAttempted`.

### 4H. Limited phantom asset handling + required diagnostics (v1.1.4)

M4.29 Create PhantomAssetHealer module
- Do: Detect “authorized but not readable/deleted” assets and heal by pruning or marking unavailable.
- Verify: Inject an invalid/unreadable assetId via Debug; opening Viewer does not crash; console prints `PhantomAssetDetected`.

M4.30 Write `phantom_asset_detected` (A.13)
- Do: Emit A.13 event with assetIdHash and auth_snapshot.
- Verify: Export logs and search `event=phantom_asset_detected`; confirm required payload fields exist.

---

## Milestone 5 — Filmstrip + Viewer + Liked (Local-only) + Favorite Sync Attempt

(Uses SwiftUI + UIKit bridge; uses GRDB for persistence; PhotoKit optional for Favorite sync.)

M5.1 Create Filmstrip component file
- Do: Create a dedicated Filmstrip view/component and wire it to workset.
- Verify: With empty workset, filmstrip not visible; after 1 shot, filmstrip becomes visible.

M5.2 Implement “newest first” ordering everywhere
- Do: Enforce newest-first ordering in workset query and UI rendering.
- Verify: Shoot 3 photos; filmstrip first item is the last shot; Viewer page 1 matches it.

M5.3 Implement state badges mapping (saving / ! / normal)
- Do: Create explicit mapping from SessionItemState to UI badge.
- Verify: Force each state via Debug; UI badges match PRD rules.

M5.4 Create ViewerContainer file (x/y, close, like)
- Do: Build Viewer shell with close button and index display.
- Verify: Open viewer from filmstrip; see “1/Total”; close returns to Camera.

M5.5 Create Zoom/Pan UIKit bridge file
- Do: Use UIScrollView-based zoom/pan wrapper.
- Verify: Pinch zoom and pan works in viewer.

M5.6 Implement scale<=1.01 treated as 1 (PRD)
- Do: Add a single threshold constant and use it for swipe enabling.
- Verify: Slight zoom 1.005 still allows swipe; zoom 1.02 disables swipe.

M5.7 Implement “pinch wins over swipe”
- Do: If pinch occurs in a gesture sequence, ignore swipe page changes.
- Verify: Pinch and move horizontally; no page flip occurs.

M5.8 Persist liked in DB (GRDB usage)
- Do: Store `liked` on session_items; toggle from viewer and filmstrip.
- Verify: Toggle liked; both UIs reflect; restart app retains liked.

M5.9 Attempt sync to system Favorites (Full access only; failure non-blocking)
- Do: If full access, attempt to set PHAsset favorite; on failure show L2 banner sessionOnce.
- Verify: Simulate failure; banner appears once; shooting/saving continues unaffected.

---

## Milestone 6 — PoseSpec Engine (Bundle-only, Deterministic, A.13 Diagnostics)

(Uses Vision + PoseSpec.json; must follow binding/rois/antiJitter/withRef/mirror rules.)

M6.1 Add PoseSpec.json to app bundle resources
- Do: Ensure PoseSpec.json is packaged in the app bundle.
- Verify: Fresh install; console prints `PoseSpecLoadedFromBundle`.

M6.2 Create PoseSpecLoader file
- Do: Loader reads PoseSpec.json and parses to an in-memory model.
- Verify: Debug “PrintPoseSpecPrdVersion” prints `v1.1.4`.

M6.3 Create PoseSpecValidator file (required fields)
- Do: Validate presence of schemaVersion/prdVersion/generatedAt/changeLog/binding/rois/sceneCatalog.
- Verify: Swap in a deliberately broken PoseSpec (Debug-only); app blocks with L3 “PoseSpec 不完整”.

M6.4 Enforce prdVersion match (PRD 4.4.1)
- Do: If mismatch, block app startup or block camera entry with L3 “版本不一致”.
- Verify: Change prdVersion (test build); app cannot proceed and explains mismatch.

M6.5 Validate binding.aliases minimal set (PRD 4.4.2)
- Do: Check required aliases exist; if any missing, block as invalid PoseSpec.
- Verify: Remove one alias (test build); app blocks with L3 “binding 缺失”.

M6.6 Validate rois dictionary (PRD 4.4.3)
- Do: Ensure faceROI/eyeROI/bgROI exist and are parseable.
- Verify: Remove eyeROI (test build); app blocks with L3 “rois 缺失”.

M6.7 Implement “portrait normalized” coordinate normalization (PoseSpec.coordinateSystem)
- Do: Normalize Vision landmarks to portrait imageNormalized space before evaluation.
- Verify: Rotate device / switch camera; Debug shows “normalizedSpace=portrait” and sign conventions remain correct.

M6.8 Create VisionPipeline files (pose + face)
- Do: Run Vision requests on preview frames to produce landmarks + confidences.
- Verify: Point at a person; Debug shows poseDetected=true and/or faceDetected=true; cover the face -> faceDetected becomes false.

M6.9 Create ROIComputer file (faceROI/eyeROI/bgROI)
- Do: Compute ROI rectangles per PoseSpec rules including clamp and eye confidence requirement.
- Verify: Debug overlays ROI boxes; eye covered -> eyeROI marked unavailable.

M6.10 Create MetricComputer file (only metrics needed by PoseSpec v1.1.4)
- Do: Implement only the metric outputs that PoseSpec cues require (no generic formula runtime for MVP).
- Verify: Debug “PrintMetricOutputs” shows numeric values for key metrics on live frames.

M6.11 Create TierScheduler file (T0 15Hz / T1 2Hz)
- Do: Schedule T0 vs T1 computations and ensure T1 never blocks preview/capture.
- Verify: Debug shows T0 tick rate >> T1; camera UI remains smooth while engine runs.

M6.12 Create CueEvaluator file (enter/warn/hard/exit)
- Do: Evaluate each cue’s thresholds for noRef and withRef.
- Verify: Debug “InjectMetricCase:FRAME_MOVE_LEFT_HARD”; selectedCueId becomes FRAME_MOVE_LEFT.

M6.13 Create CueSelector file (priority+severity+mutex per PoseSpec.defaults.selection)
- Do: Implement pickOneCue and tie-breaker order.
- Verify: Debug inject two competing cues; selected cue matches expected tie-breaker; console prints selection rationale.

M6.14 Create AntiJitterGate file (persistFrames/minHoldMs/cooldownMs)
- Do: Enforce stability constraints; exit cooldown prevents flicker.
- Verify: Near-threshold movement does not cause rapid cue switching; cue stays >=3s; cooldown prevents immediate re-trigger.

M6.15 Create PraiseController file (PoseSpec.praisePolicy)
- Phase 1 [内核层/纯逻辑] (必须)
  - Task-Logic: 定义 PraisePolicy/PraiseState/PraiseOutput 与 PraiseController 状态机。
    - 规则：exit_crossed 触发；同一 mutexGroup 10s 冷却；冻结脚本 5s 或 shutter_tap 解除。
  - Task-Test: 单元测试覆盖：
    - Happy Path：exit_crossed -> freeze -> timeout 5s 解除
    - Edge Cases：冷却期内不重复触发；shutter_tap 立即解除；重复 exit 不抖动
  - Verification Instruction:
    - 运行 XCTest，验证 cooldown/timeout/shutter_tap 三类路径。

- Phase 2 [数据/胶水层] (按需)
  - Task-Glue: 将 CueSelector/CueEvaluator 的 exit_crossed 事件转换为 PraiseController 事件。
  - Task-Glue: 将 shutter_tap 转换为 PraiseController 事件，确保冻结立即解除。
  - Verification Instruction:
    - DebugTools/Console 输出 Praise 状态变化（freeze/unfreeze/cooldown）。

- Phase 3 [UI/交互层] (最后)
  - Task-UI: 将 PraiseOutput 绑定到 Camera UI（显示“就现在！按快门”）。
  - Task-UI: 处理安静模式与 UI 折叠策略（若已有脚本卡/夸夸 overlay）。
  - Verification Instruction:
    - 真机/模拟器运行，exit_crossed 时 UI 立即锁定；5s 超时解除；shutter 立即解除。

- Phase 4 [集成验收] (收尾)
  - Task-Verify: 联调完整拍摄链路，确认“UI 安静但不达标”不发生。
  - Verification Instruction:
    - 手工脚本：接近阈值抖动时不重复夸夸；满足 exit 才触发；冷却期内不重复。

### withRef (target extraction + mirror + match-blocked-by logs)

M6.16 Create RefTargetExtractor file (compute target outputs from ref image)
- Phase 1 [内核层/纯逻辑] (必须)
  - Task-Logic: 新增 RefTargetExtractor，输入静态参考图（CGImage/PixelBuffer + orientation），输出 target.* 所需的 Metric 输出（不保存像素）。
  - Task-Logic: 复用与实时一致的链路：Vision -> ROIComputer -> MetricComputer；输出键集合必须与 MetricContract 对齐。
  - Verification Instruction:
    - Debug/Unit: 对同一张 ref 连续提取两次，目标输出 diff <= 1e-3。

- Phase 2 [胶水/调试] (可并行)
  - Task-Glue: 提供 DebugTools 入口或 debug helper，允许传入一张本地图片触发 RefTargetExtractor 并打印 target outputs。
  - Verification Instruction:
    - Debug: 触发一次提取后，控制台输出 target.* 键集合与数值；无像素持久化痕迹。

- Phase 3 [测试] (可并行)
  - Task-Test: 为 RefTargetExtractor 增加可重复的测试（静态样本或 stub Vision 输出），覆盖：
    - 稳定性：同图两次结果 diff <= 1e-3。
    - 不可用：缺 landmarks/ROI 时返回 unavailable reason（不崩溃）。
  - Verification Instruction:
    - XCTest: 运行相关单测；稳定性与不可用路径均通过。

M6.17 Store RefTarget in session-scoped storage (and clear on reset)
- Do: Store target outputs tied to current session; clearing session clears all targets.
- Verify: After reset session, Debug shows “targetPresent=false”.

M6.18 Create MirrorEvaluator (x=0.5)
- Do: Compute both mirrored and non-mirrored error; pick smaller; record mirrorApplied internally.
- Verify: Use mirrored live pose vs ref; match improves when mirror enabled; diagnostics show mirrorApplied=true.

M6.19 Create MatchDecider = “PoseSpec exit equivalence” (PRD 5.1.1.a)
- Do: Define Match true iff all required dimensions satisfy exit for >=persistFrames; no hard-coded thresholds.
- Verify: Create scenario “UI quiet but one dimension not exit”; Match remains false.

M6.20 Emit `withref_match_state` (A.13)
- Do: Write match state with required_dimensions and blocked_by; blocked_by must be non-empty when match=false and UI quiet.
- Verify: Reproduce “quiet but not match”; export logs show withref_match_state with blocked_by non-empty.

M6.21 Emit `withref_fallback` (A.13)
- Do: When missing ROI/landmarks/confidence, emit fallback reason and missing list.
- Verify: Cover an eye; export logs show withref_fallback with reason referencing eyeROI missing.

---

## Milestone 7 — Reference Images (Import, Gates, Copy-to-Album, Overlay, Limits)

(Uses Vision + PhotoKit; stores ref metadata + targets in GRDB.)

M7.1 Create RefItem model file (DB-backed)
- Do: Define RefItem fields needed for MVP: refId/sessionId/createdAt/assetId/isSelected/targetOutputs.
- Verify: Debug “AddDummyRefItem”; DB shows ref count increments; restarting app preserves count.

M7.2 Create ReferencePicker module (user photo picker)
- Do: Add “Add Reference” action to Camera bottom bar that opens system picker.
- Verify: Tap Add Reference; system picker appears; cancel returns to Camera.

M7.3 Implement “first ref save notice” installOnce prompt (PRD 5.2)
- Do: On first successful save-to-album of a ref in app lifetime, show L3 notice once.
- Verify: First ref import shows notice; second ref import does not show notice.

M7.4 Create RefGateEvaluator file (strong thresholds 5.2.1)
- Do: Implement deterministic rejection reasons: multi-person, face too small, eyes not visible, shoulders missing.
- Verify: For each test photo type, import is rejected with correct reason text.

M7.5 Multi-person gate (>=2 faces with confidence>=0.6)
- Do: Run Vision face detection on selected image; reject if >=2.
- Verify: Pick a group photo; app rejects and shows “多人” reason.

M7.6 Face too small gate (areaRatio<0.02 OR widthRatio<0.12)
- Do: Compute face bbox ratios in normalized space.
- Verify: Pick a far-away face photo; reject with “脸太小” and next-step suggestion.

M7.7 Eyes not visible gate (either eye conf<0.5)
- Do: Check eye center confidence.
- Verify: Pick profile/occluded eyes photo; reject with “看不到眼睛”.

M7.8 Upper body incomplete gate (either shoulder conf<0.5)
- Do: Check shoulder landmark confidence.
- Verify: Pick cropped upper-body photo; reject with “上半身不全”.

M7.9 Rejection prompt + copy does not proceed
- Do: When rejected, show L3 ref_reject prompt; do not save/copy; do not change current ref.
- Verify: Reject a ref; system album has no new “ref copy”; current overlay remains unchanged.

M7.10 On accept: copy ref to system “Just Photo” album (PRD 5.2)
- Do: Save a copy to Photos and add to Just Photo album; mark as ref in DB.
- Verify: After accept, Photos app shows ref copy inside “Just Photo” album.

M7.11 Ref copies limit = 10 per session
- Do: Track count in session; block on 11th with strong prompt; reset_session resets the limit.
- Verify: Import 10 refs succeeds; 11th blocked; reset session allows importing again.

M7.12 Create ReferenceOverlay UI files
- Do: Create overlay component with: 60% opacity, two sizes (20%/30% of preview short side), draggable, hide/show, prev/next.
- Verify: Overlay appears after selecting a ref; toggling size changes visibly; hide removes overlay.

M7.13 Enforce drag clamp + cannot cover shutter button
- Do: Clamp overlay within safe region; prevent overlay from covering shutter.
- Verify: Try dragging overlay onto shutter; overlay stops short and shutter remains unobstructed.

M7.14 Prev/Next switching among refs
- Do: Implement switching current ref; update overlay image accordingly.
- Verify: With 2+ refs imported, tapping next/prev changes overlay image each time.

M7.15 Reset session clears ref list + target outputs
- Do: Reset clears DB refs for that session and clears in-memory targets.
- Verify: After reset, ref overlay disappears and ref count returns to 0.

---

## Milestone 8 — Inspiration Sheet (ODR + Offline Keywords + Auto Retry)

(Uses On-Demand Resources + NWPathMonitor; logs A.13 odr_auto_retry.)

M8.1 Create InspirationState enum file (4 states)
- Do: Define ready/downloading/failed_retry/offline_keywords_only.
- Verify: Debug “ForceInspirationState” cycles through states and UI updates.

M8.2 Create KeywordCatalog file (local keywords by scene)
- Do: Store keywords locally (no network) for cafe/outdoor.
- Verify: Airplane mode; open Inspiration; keywords still visible.

M8.3 Create ODRManager module
- Do: Wrap NSBundleResourceRequest by tag; support start/cancel; report progress.
- Verify: Tap a specific ODR image; state becomes downloading and progress increases.

M8.4 Implement “tap image => request tag download”
- Do: Only download the selected image pack/tag; do not bulk download.
- Verify: Tap different images; only the selected tag shows download progress; cancel stops progress.

M8.5 Implement failed_retry state (with retry button)
- Do: On download error, show failed_retry with reason and Retry.
- Verify: Simulate ODR failure; UI shows failed_retry; tapping Retry re-enters downloading.

M8.6 Implement offline_keywords_only state when no network
- Do: Use NWPathMonitor for network status; when unsatisfied, hide/disable ODR grid and show keywords only.
- Verify: Turn off network; Inspiration shows keywords-only state.

M8.7 Implement auto retry on network recovery (debounce 500ms, once per recovery)
- Do: When in failed_retry and network becomes satisfied, wait 500ms then auto trigger one retry; stop listening when leaving sheet.
- Verify: Force failed_retry offline; restore network; without tapping, auto retry starts; A.13 log includes `odr_auto_retry` with debounce_ms=500.

M8.8 Emit `odr_auto_retry` (A.13)
- Do: Write event with state_before=failed_retry, debounce_ms=500, result success|fail|skipped_left_page.
- Verify: Export logs; search `event=odr_auto_retry`; confirm payload fields exist.

---

## Milestone 9 — Wrap/Collage (1×3, 2×2, Export, Fail States)

(Uses CoreGraphics/UIGraphicsImageRenderer + PhotoKit + share sheet; must block entry if write_failed exists.)

M9.1 Create WrapEntryRule module
- Do: Gate: show Wrap button only if workset_count>=3; if write_failed exists, block.
- Verify: With 2 photos Wrap button hidden; with 3 photos visible; with write_failed, tapping shows blocking prompt.

M9.2 Create WrapState model file (selected template + selected items)
- Do: Store chosen template and selected itemIds (session-scoped).
- Verify: Select a template and some photos; leave and re-enter Wrap; selections persist within session.

M9.3 Implement default selection rule
- Do: On first enter, auto select latest N items where N depends on template; does not require liked.
- Verify: With 4 shots, enter Wrap; latest 3 or 4 are selected based on template.

M9.4 Implement template switcher (only 1×3 and 2×2)
- Do: Provide only two templates; switching updates required slot count.
- Verify: Toggle templates; UI shows exactly 3 or 4 slots.

M9.5 Implement “tap slot -> open bottom picker -> replace”
- Do: Slot selection opens a bottom chooser from current session items; selecting replaces that slot.
- Verify: Replace a slot; preview changes immediately.

M9.6 Create CollageRenderer module (fixed 1080×1920, center-crop)
- Do: Render output image with deterministic size and center-crop per cell.
- Verify: Export result; inspect image dimensions in Photos info: 1080×1920.

M9.7 Save collage to Photos (PhotoKit)
- Do: Save exported collage to system Photos; attempt to add to Just Photo album.
- Verify: Export success; collage appears in Photos; if album add works, it appears in Just Photo album.

M9.8 Share sheet flow (user cancel is not an error)
- Do: After generating collage, present share sheet; cancel does not show error prompt.
- Verify: Tap Share then cancel; no error banner/modal appears.

M9.9 Fail states: permission denied
- Do: If Photos permission prevents saving, show L3 “无法保存拼图” with Go Settings/Cancel.
- Verify: Deny Photos permission; export triggers that L3.

M9.10 Fail states: low storage
- Do: If disk space low, show L3 “存储空间不足” with action to clean up.
- Verify: Simulate low space via Debug; export triggers that L3.

M9.11 Fail states: render failure
- Do: If renderer fails, show L3 “生成失败，请重试”.
- Verify: Debug “ForceRenderFail”; export shows that L3; retry triggers another attempt.

---

## Milestone 10 — Settings (Permissions, Import, Gridlines, Logs, Pro Entry)

M10.1 Create SettingsState storage keys (GRDB usage)
- Do: Persist toggles like “gridlines enabled” using GRDB.
- Verify: Toggle gridlines; restart app; setting persists.

M10.2 Implement gridlines overlay in Camera preview
- Do: Show/hide composition grid based on setting.
- Verify: Toggle setting; gridlines appear/disappear instantly.

M10.3 Add “Manage Selected Photos” (Limited Picker) entry
- Do: When in Limited mode, provide entry to open system limited library picker.
- Verify: In Limited mode, tapping opens iOS picker; adding photos expands readable set.

M10.4 Add “Open System Settings” entry
- Do: Provide direct jump to app’s Settings page.
- Verify: Tap entry; iOS Settings opens to this app.

M10.5 Add “Import Photos to Session” entry
- Do: System picker selects photos; imported photos become SessionItems (imported state can be represented but must count toward 20 limit).
- Verify: Import 3 photos; they appear in filmstrip; workset_count increases accordingly.

M10.6 Enforce 20 limit during import
- Do: If import would exceed 20, block and show L3 guidance (clear/reset/wrap).
- Verify: At 19 items, try importing 2; app blocks and count does not exceed 20.

M10.7 Wire “Export Diagnostics Logs” in Settings (from Milestone 1)
- Do: Ensure it’s visible and functional in Settings.
- Verify: Export produces files and share sheet appears.

M10.8 Add Pro card entry to open Paywall
- Do: Pro card opens Paywall sheet.
- Verify: Tap card; Paywall appears; dismiss returns.

---

## Milestone 11 — Paywall + StoreKit 2 (Purchase, Restore, Failure Prompts, Expiry Downgrade)

M11.1 Create StoreKitManager module
- Do: Wrap product loading, purchase, restore, entitlement status.
- Verify: In StoreKit test env, Paywall shows products with price text populated.

M11.2 Implement “current entitlement status” display
- Do: Paywall/Settings show subscribed/trial/expired states.
- Verify: Purchase in test env; status flips to subscribed; app relaunch retains status.

M11.3 Implement purchase flow (success path)
- Do: Purchase monthly/yearly; confirm completion; update UI.
- Verify: Purchase succeeds; status changes; no error prompt shown.

M11.4 Implement restore flow (success path)
- Do: Restore purchases and update UI.
- Verify: With an existing subscription, restore sets status to subscribed.

M11.5 Implement purchase failure L3 (PRD)
- Do: On failure/no network, show L3 “无法完成购买” with actions: Retry / Later / Check Network.
- Verify: Disable network; tap purchase; L3 appears with those buttons.

M11.6 Implement restore failure L3 (PRD)
- Do: On restore failure/no network, show L3 “恢复失败” with actions: Retry / Later / Manage Subscription.
- Verify: Disable network; tap restore; L3 appears; Manage Subscription opens system UI.

M11.7 Implement expiry downgrade rules (PRD E4)
- Do: When expired, disable script cards + praise overlay; keep camera capture/save fully functional.
- Verify: Force expired via Debug; Camera still shoots and saves; script/praise UI not shown.

---

## Milestone 12 — Down Reasons Sheet (Local-only, >=10 shows)

M12.1 Add entry visibility rule (>=10 photos)
- Do: Only show “不好看” entry when workset_count>=10.
- Verify: At 9 items entry hidden; after 10th item entry appears.

M12.2 Create DownReasons catalog file
- Do: Define a minimal list of reasons (local only).
- Verify: Open sheet; list displays consistently.

M12.3 Implement selection (single-select MVP)
- Do: Selecting one reason closes sheet and stores locally (GRDB or local_stats).
- Verify: Select a reason; sheet dismisses; Debug “PrintLastDownReason” prints selected value.

M12.4 Log selection locally (diagnostics)
- Do: Emit a local event line for down_reason_select (still local-only).
- Verify: Export logs; search for down_reason_select; confirm includes scene and session_id.

---

## Milestone 13 — Performance SLO + QA Regression Hooks (Local-only)

M13.1 Add camera-ready timer (PRD 4.1.1)
- Do: Measure from Camera viewDidAppear to shutter enabled; record locally.
- Verify: Debug “PrintLastCameraReadyMs” prints a value after camera becomes ready.

M13.2 Record thumb replacement latency (shutter -> thumb_ready)
- Do: For each item, record time until thumb_ready; mark thumb_failed at 5s as already required.
- Verify: After a shot, Debug “PrintLastThumbLatency” prints value; exported logs show latency fields.

M13.3 Record viewer first-frame latency
- Do: Measure from tapping filmstrip item to viewer showing image content; handle slow cases with placeholder and retry.
- Verify: Debug “PrintLastViewerFirstFrameMs” prints value; slow-load simulation shows placeholder UI.

M13.4 Implement thermal / dropped-frames degrade rules (PRD 4.4.6)
- Do: When thermalState>=serious or dropped frames condition met, disable all T1 cues then reduce T0 updateHz to 8; recover gradually.
- Verify: Debug “ForceThermalSerious”; T1 stops updating; T0 rate lowers; shutter/save unaffected.

M13.5 QA asset harness entry (PoseSpec.qaAssets naming convention)
- Do: Add Debug-only screen that can run engine evaluation on a selected QA before/after image and report selectedCueId + cleared/not.
- Verify: Select a known cue’s before image: result says “must trigger”; select after image: result says “must clear”.

M13.6 A.13 acceptance checks (must be demonstrable)
- Do: Ensure these are all producible:
  - quiet but match=false => withref_match_state.blocked_by non-empty
  - phantom asset => phantom_asset_detected
  - fetch retry => photo_write_verification.retry_used=true and verified_within_2s=true
- Verify: Run the three scenarios and export logs; search each event and confirm required payload fields.

---

## Final MVP “No Remote Data” Audit (must pass before TestFlight)

F.1 Dependency audit
- Do: Ensure no analytics SDKs, no custom upload endpoints, no photo uploads; only Apple/ODR/StoreKit traffic.
- Verify: Use iOS network debugging (or a local proxy) during a session; observe no non-Apple endpoints contacted.

F.2 PRD QA checklist run (Section 10)
- Do: Execute PRD QA checklist end-to-end and record results locally (notes can be stored in a local file).
- Verify: Export diagnostics logs and confirm key flows are represented (camera init, save states, prompts, withRef, ODR auto retry).

---

## Optimization Todo (Follow-ups)

- 4E (Tracker内存态): make `CaptureFailureTracker` resilient across background/terminate (persist rolling window + last trigger time), so abnormal prompts don't reset unexpectedly.
- 4D (Error Reason): plumb PhotoKit write failures into `WriteFailReason` (store reason payload/text on `session_items`, show exact reason in Viewer/Camera prompts) instead of a generic message.
