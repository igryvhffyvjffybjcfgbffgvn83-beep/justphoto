# Architecture

This document is the project’s current “source of truth” for architecture. It is derived from:
- `memory-bank/product-requirement.md`
- `memory-bank/tech-stack.md`

Constraints (must hold at all times):
- Local-only data: no accounts, no remote analytics, no photo uploads.
- Data Safety: photos must be written to system Photos; `write_failed` must block shutter until resolved.
- PoseSpec is bundle-only and version-locked to PRD v1.1.4 (`prdVersion` mismatch is a blocker).
- Diagnostics logs are local-only, exportable, and follow PRD Appendix A.13 (JSON Lines, 50MB/30d rotation).

## High-Level System Architecture

The app is a single-device, offline-first iOS app with these major subsystems:

1) UI Shell (SwiftUI)
- Camera is the primary screen.
- All other experiences are sheets/overlays/modals: Settings, Paywall, Inspiration, Viewer, Wrap, Down Reasons.
- UIKit bridging is used only where SwiftUI is a poor fit (camera preview layer, viewer zoom/pan).

2) Camera & Capture (AVFoundation)
- Owns the live preview pipeline and the “tap shutter -> image data” pipeline.
- Must not be blocked by PoseSpec evaluation or thumbnail generation.
- Camera permission state is represented as a PRD-aligned enum (`CameraAuth`) derived from `AVAuthorizationStatus` for `.video`.
- When permission is `not_determined`, the Camera screen presents a pre-permission L3 prompt (Continue/Cancel). Continue will be wired to the system permission dialog in M3.3.
  - M3.3 wires Continue to `AVCaptureDevice.requestAccess(for: .video)` via `CameraAuthMapper.requestVideoAccess()`.
 - When permission is `denied` or `restricted`, Camera shows a placeholder (no live preview) and disables shutter, plus an L2 banner on Camera:
   - denied: message `未获得相机权限，无法拍照` with action `去设置` (opens system Settings)
   - restricted: message `相机受系统限制，无法使用` with action `了解`
 - Warmup state is tracked by `WarmupTracker` (starts on Camera entry when permission is authorized):
    - Immediately shows a warmup overlay
    - Upgrades messaging after 3s
    - Fails after 8s and shows an L3 modal.
      - The failure modal includes a reason explanation from `CameraInitFailureReason` (Debug can simulate reasons until real camera init exists).
      - If reason is `permission_denied`, the modal offers a `去设置` action.
      - The failure modal includes a `重试` action that triggers a warmup restart and prints `CameraInitRetry`.

3) Save Pipeline & Photos Integration (PhotoKit)
- Writes captured photos to system Photos.
- After `finalized`, runs Asset Fetch Verification Retry (immediate fetch, then 500ms retry once).
- Adds assets to the “Just Photo” album; failures set `album_state=failed` (non-blocking) and support retries.
- Limited Access support includes phantom asset healing and `phantom_asset_detected` diagnostics.
- When a user toggles `liked`, the app attempts to sync to system Favorites (`PHAsset.isFavorite`) only when Photos auth is Full; failures are non-blocking and show a sessionOnce L2 banner.

4B) Capture Pipeline Ownership
- `CaptureCoordinator` is the single owner of the capture/save pipeline state machine (serializes work via an internal actor).
- Camera routes shutter taps to `CaptureCoordinator.shared.shutterTapped()`.

M4.7 (Shutter tap gate checks):
- Capture pipeline reads session counters and blocks capture if any hard gate is hit: `write_failed > 0`, `in_flight >= 2`, `workset_count >= 20`.
- When blocked, pipeline prints `CaptureSkipped:blocked` and does not start capture / create an item.

M4.8 (Optimistic item insert):
- After gates pass, capture pipeline inserts a `session_items` row immediately with state `captured_preview`, stable `item_id`, and monotonic `shot_seq`.
- The insert is flushed immediately (`DBFlushed: optimistic_insert`) so kill/relaunch still shows the item.

M4.9 (PendingFileStore):
- Pending files live under `Application Support/JustPhoto/pending`.
- `pending_file_rel_path` is stored in DB relative to `Application Support/JustPhoto` (example: `pending/<itemId>.<ext>`).
- Writes are atomic (tmp write, then rename/replace); supports deletion.

M4.10 (Capture data deadline):
- After optimistic insert, pipeline must produce a readable pending file within 2.0s.
- If the deadline is missed (no pending file), the optimistic item is removed from workset/DB and a `capture_failed` L1 toast ("没拍到") is shown.

M4.11 (PhotoKit write after pending exists):
- Pipeline transitions `captured_preview -> writing` only after the pending file is written and `pending_file_rel_path` is persisted.
- PhotoKit save writes `asset_id` and transitions `writing -> finalized` (or `writing -> write_failed` on error).

M4.12 (Immediate fetch verification):
- After `finalized`, pipeline immediately fetches `PHAsset` by `asset_id` once and records an A.13 `photo_write_verification` event (includes `first_fetch_ms`).

M4.13 (Fetch retry once):
- If the first fetch returns empty, pipeline retries once after 500ms and records `retry_used=true`, `retry_delay_ms=500`, and `verified_within_2s` in the same A.13 `photo_write_verification` event.

Project-level configuration notes:
- This project uses Xcode-generated Info.plist (`GENERATE_INFOPLIST_FILE=YES`). Privacy strings are set via build settings `INFOPLIST_KEY_*` in `justphoto_opencode.xcodeproj/project.pbxproj`.
- Step M0.4 adds the required usage descriptions: Camera, Photo Library (read), Photo Library (add).
- Swift Package dependencies are locked by Xcode SwiftPM in `justphoto_opencode.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved` (ensures reproducible dependency versions).

4) Session System (Business Session; not AVCaptureSession)
- A “Session” is a local workset (max 20) that drives filmstrip/viewer/wrap.
- Persistence is via SQLite (GRDB) plus file-based caches for pending writes and thumbnails.
- Must survive kill/relaunch with recoverable `write_failed` items.

SessionItem 状态拆分为两个独立状态：

thumbnail_state:
- pending
- ready
- failed

album_state:
- none
- adding
- added
- failed

核心 session.state 不再包含 thumb/album 状态字段。

M4.14 (write_failed reasons):
- `WriteFailReason`: `no_permission`, `no_space`, `photo_lib_unavailable`, `system_pressure`.
- A.10 mapping to user-facing Chinese short phrases is centralized (used for `未保存到系统相册（{reason}）`).

M4.4 (Workset full flow):
- When `workset_count >= 20`, Camera shows a blocking L3 modal (`workset_20_limit_modal`) with actions: clear unliked, go wrap, reset session, cancel.
- After cancelling, an L2 banner (`workset_20_full_banner`) persists while full and can reopen the modal.
- Clearing unliked deletes `liked=0` items except critical states (`write_failed`, `writing`, `captured_preview`).

5) PoseSpec Engine (Vision + PoseSpec.json)
- Reads PoseSpec from the app bundle, validates contracts (binding/rois/prdVersion), and evaluates cues.
- Runs a tiered scheduler: T0 (pose/face geometry) up to 15Hz; T1 (ROI/frame metrics) up to 2Hz.
- Provides: single cue selection, anti-jitter, praise policy, withRef matching (including mirror evaluation).
- Emits A.13 diagnostics events for match state, fallbacks, and related invariants.
  - Bundle resource: `PoseSpec.json` is shipped inside the app bundle (M6.1).
  - Loader: `PoseSpecLoader` loads and decodes PoseSpec from the bundle (M6.2).
  - Validator: `PoseSpecValidator` enforces required PoseSpec keys; invalid PoseSpec blocks Camera via a L3 modal (M6.3).
  - Version gate: `PoseSpecValidator.validatePrdVersion(expected:)` blocks Camera when prdVersion mismatches (M6.4).
  - Binding gate: `PoseSpecValidator.validateBindingAliasesMinimalSet` blocks Camera when required binding aliases/sets are missing (M6.5).
  - ROI gate: `PoseSpecValidator.validateRoisDictionary` blocks Camera when faceROI/eyeROI/bgROI are missing or not parseable (M6.6).
  - Coordinate system: `PoseSpecCoordinateNormalizer` normalizes points into portrait imageNormalized space before evaluation (M6.7).
  - Vision pipeline (M6.8):
    - `justphoto_opencode/Infrastructure/PoseSpec/VisionPipeline.swift` runs `VNDetectHumanBodyPoseRequest` + `VNDetectFaceLandmarksRequest` on preview frames and exposes `poseDetected/faceDetected` for debug verification.
    - `justphoto_opencode/Infrastructure/Camera/CameraFrameSource.swift` provides preview frames via `AVCaptureVideoDataOutput`.
    - `justphoto_opencode/Infrastructure/Camera/CameraPreviewView.swift` renders a real `AVCaptureVideoPreviewLayer`.
    - `justphoto_opencode/Features/Camera/CameraScreen.swift` wires preview + Vision processing and only runs it when `cameraAuth == .authorized` and `poseSpecValid == true`.
  - ROI computer (M6.9):
    - `justphoto_opencode/Infrastructure/PoseSpec/ROIComputer.swift` computes `faceROI` (padded bbox), `eyeROI` (from eye centers + inter-ocular distance; requires eyes), and `bgROI` as a 4-rect ring (`frame - faceROI`).
    - `justphoto_opencode/Infrastructure/Camera/CameraPreviewView.swift` overlays ROI rectangles (debug visualization) aligned to the preview layer.
  - T1 frame metrics (M6.10 Phase 4):
    - `justphoto_opencode/Infrastructure/PoseSpec/FrameMetricComputer.swift` computes pixel metrics (e.g. `faceLumaMean`) from `CVPixelBuffer` via Accelerate/vImage with 2Hz throttling.
    - `justphoto_opencode/Infrastructure/PoseSpec/MetricComputer.swift` merges T1 outputs; `VisionPipeline` injects `pixelBuffer` and ROIs into `MetricContext`.
  - Ref target extractor (M6.16):
    - `justphoto_opencode/Infrastructure/PoseSpec/RefTargetExtractor.swift` extracts `target.*` metrics from reference input; supports CGImage and CVPixelBuffer entry points for static/live debug flows.
  - Tier scheduler (M6.11):
    - `justphoto_opencode/Infrastructure/PoseSpec/VisionPipeline.swift` defines `TierScheduler` with a latest-frame gate, T0 (15Hz) + T1 (2Hz) timers, per-tier serial queues, and in-flight skip gates.
    - `justphoto_opencode/Features/Camera/CameraScreen.swift` sends camera frames to `TierScheduler` (O(1) cache in the frame callback).
    - Thermal degradation: when system thermal state >= serious, pause T1 and drop T0 target to 8Hz (restores when thermal recovers).
    - T0 Vision runs as async dispatch on a dedicated Vision perform queue; the T0 in-flight gate only protects scheduling (not model runtime), preventing queue starvation.
    - Observability: `TierScheduler` prints 1Hz aggregate logs with ticks/s, avg/max durations, in-flight skip counts, and T0 timeouts.
    - DebugTools: can inject a Vision delay to validate T0 timeout behavior.
  - Cue evaluator (M6.12 Phase A):
    - `justphoto_opencode/Infrastructure/PoseSpec/CueEvaluator.swift` evaluates cue thresholds (noRef/withRef) and returns a single level (hard > warn > enter > exit > none).
    - `justphoto_opencode/Features/Settings/DebugToolsScreen.swift` includes a debug injection button for stateless evaluation (FRAME_MOVE_LEFT_HARD).
  - Cue stability (M6.12 Phase B):
    - `justphoto_opencode/Infrastructure/PoseSpec/CueStabilityLayer.swift` applies frame-count stability (hard/exit require 2 consecutive frames).
    - `justphoto_opencode/Features/Settings/DebugToolsScreen.swift` prints `stableFrameCount` and `stabilityState` for injected evaluation.
  - Praise controller (M6.15):
    - Core API contract (parallel dev contract; implementation must honor PoseSpec.praisePolicy):
      ```swift
      protocol PraiseControlling {
          func reset()
          // Called when a cue crosses exit; mutexGroup is used for cooldown.
          func handleExitCrossed(cueId: String, mutexGroup: String, timestampMs: Int) -> PraiseOutput
          // Called on shutter tap to unfreeze immediately.
          func handleShutterTap(timestampMs: Int) -> PraiseOutput
          // Called periodically to resolve timeout-based unfreeze.
          func tick(timestampMs: Int) -> PraiseOutput
          var state: PraiseState { get }
      }

      struct PraiseState {
          var frozenUntilMs: Int?
          var lastPraiseByMutexGroup: [String: Int]
          var frozenScriptZh: String?
      }

      struct PraiseOutput {
          let isFrozen: Bool
          let scriptZh: String?   // “就现在！按快门” during freeze
          let reason: String      // freeze / unfreeze / cooldown / noop
      }
      ```
    - Required behavior:
      - exit_crossed triggers freeze; cooldown 10s per mutexGroup; freeze auto-times out at 5s or on shutter tap.
  - Cancel semantics probe (M6.x):
    - `justphoto_opencode/Infrastructure/Camera/WarmupState.swift` adds a DEBUG-only cancel probe to verify warmup cancellation safety.
    - `justphoto_opencode/Infrastructure/Capture/CaptureCoordinator.swift` adds a DEBUG-only cancel probe for deadline cancellation.
    - `justphoto_opencode/Infrastructure/Capture/AlbumAddRetryScheduler.swift` adds a DEBUG-only cancel probe for retry cancellation.
    - `justphoto_opencode/Features/Settings/DebugToolsScreen.swift` exposes `CancelSemanticsProbe` to run all probes.

6) Prompt System (L1/L2/L3)
- Centralized, contract-driven prompt presenter (Toast/Banner/Modal) with mutual exclusion and throttling.
- Prompt frequency gates are enforced by `PromptCenter`.
  - `FrequencyGate.sessionOnce` persists a per-session "shown" flag in SQLite (`sessions.flags_json`) so a prompt can be shown at most once per session (survives kill/relaunch).
- Prompt supports up to 4 actions (primary/secondary/tertiary/quaternary) for multi-option modals.
- Logs prompt show/dismiss/action locally (A.12 recommended, local only).
  - Events are appended to the existing local JSONL diagnostics log (same rotation/export path as A.13).
  - Event names: `prompt_shown`, `prompt_dismissed`, `prompt_action_tapped`.
  - Implementation:
    - `justphoto_opencode/Infrastructure/Diagnostics/DiagnosticsLogger.swift` defines `DiagnosticsEventWriter` (actor) with prompt event helpers.
    - `justphoto_opencode/Infrastructure/Prompt/PromptCenter.swift` calls the writer on show/dismiss/action and includes `preempt` as a dismiss reason. It also exposes an `actionPublisher` for non-prompt UI code to react to button taps.
- VoiceOver changes toast/banner timing (no in-app TTS).
  - `justphoto_opencode/Infrastructure/Prompt/PromptTimings.swift` centralizes PRD timing constants and applies VoiceOver minimums.
  - `justphoto_opencode/ContentView.swift` hosts `PromptHostOverlay` which schedules auto-dismiss tasks for toast and for banners that have no primary button; VoiceOver detection uses `UIAccessibility.isVoiceOverRunning` with a SwiftUI environment fallback.

Debug-only UI policy:
- Debug Tools UI is guarded by `#if DEBUG` in `justphoto_opencode/Features/Settings/SettingsSheet.swift` and `justphoto_opencode/Features/Settings/DebugToolsScreen.swift`.
- Project build settings explicitly prevent `DEBUG` from being defined in Release (see `SWIFT_ACTIVE_COMPILATION_CONDITIONS` in `justphoto_opencode.xcodeproj/project.pbxproj`).

Debug Tools currently include:
- A `DebugToolsPing` button in `justphoto_opencode/Features/Settings/DebugToolsScreen.swift` that prints `DebugToolsPing` to Xcode console for quick plumbing verification.
- A `PrintCameraAuth` button in `justphoto_opencode/Features/Settings/DebugToolsScreen.swift` that prints the mapped PRD permission state for `.video`.
- Prompt test buttons in `justphoto_opencode/Features/Settings/DebugToolsScreen.swift`:
  - `ShowTestToast`
  - `ShowTestBannerWithButton`
  - `ShowTestBannerAutoDismiss`
- M4.3 helpers (15-count banner gate verification): seed workset to 14, insert 1 item to hit 15, print/clear the per-session prompt gate flag.

7) Inspiration (ODR + Network.framework)
- ODR downloads reference images on-demand.
- Offline degrades to keywords-only.
- When in failed_retry, network recovery triggers a single auto-retry after 500ms debounce and logs `odr_auto_retry`.

8) Wrap/Collage
- Generates a deterministic 1080x1920 collage for two templates (1x3, 2x2).
- Saves to Photos and shares via system share sheet.
- Entry is blocked if any `write_failed` exists.

9) Purchases (StoreKit 2)
- Subscription gates only “script card + praise” features.
- Capture and saving to Photos always remain available, even when expired.

## Planned Repository / File Layout

Top-level:
- `memory-bank/` (documents as source of truth)
- `App/` (app entry, root navigation)
- `Features/`
- `Infrastructure/`
- `Resources/` (PoseSpec, local catalogs, ODR metadata)

Current Xcode project (already present):
- `justphoto_opencode.xcodeproj/` (Xcode project + scheme)
- `justphoto_opencode/` (app source folder)

Step M0.3 UI shells (SwiftUI, no business logic yet):
- `justphoto_opencode/Features/Camera/CameraScreen.swift` (main entry shell; presents sheets; links to Viewer/Wrap)
- `justphoto_opencode/Features/Viewer/ViewerScreen.swift` (viewer shell)
- `justphoto_opencode/Features/Settings/SettingsSheet.swift` (settings shell)
- `justphoto_opencode/Features/Paywall/PaywallSheet.swift` (paywall shell)
- `justphoto_opencode/Features/Inspiration/InspirationSheet.swift` (inspiration shell)
- `justphoto_opencode/Features/Wrap/WrapScreen.swift` (wrap shell)
- `justphoto_opencode/Features/DownReasons/DownReasonsSheet.swift` (down reasons shell)

Entry wiring (current):
- `justphoto_opencode/ContentView.swift` -> shows `CameraScreen`

Scaffolding folders created in repo root (Step M0.2):
- `App/` (reserved for app entry/root navigation wiring)
- `Features/` (feature modules: Camera/Viewer/Settings/Paywall/Inspiration/Wrap/DownReasons)
- `Infrastructure/` (shared services: Diagnostics/Prompt/Session/Photos/PoseSpec/Network/Purchases)
- `Resources/` (bundle resources: PoseSpec, local catalogs, ODR metadata)

Note:
- `.gitkeep` files exist only to allow Git to track empty directories during early scaffolding.

Diagnostics module scaffolding (Step M1.1):
- `justphoto_opencode/Infrastructure/Diagnostics/DiagnosticsEvent.swift` (event model placeholder)
- `justphoto_opencode/Infrastructure/Diagnostics/DiagnosticsLogger.swift` (logging façade placeholder)
- `justphoto_opencode/Infrastructure/Diagnostics/DiagnosticsRotationManager.swift` (rotation policy placeholder)
- `justphoto_opencode/Infrastructure/Diagnostics/DiagnosticsExporter.swift` (export/share placeholder)

Diagnostics event contract (Step M1.2):
- `DiagnosticsEvent` encodes a single JSON line with required top-level keys: `ts_ms`, `session_id`, `event`, `scene`, `payload`.
- `DiagnosticsLogger.encodeJSONLine(...)` produces the JSON line string (file writing/export are implemented in later steps).

Diagnostics JSONL append (Step M1.3):
- `DiagnosticsLogger.appendJSONLine(...)` appends a single JSON line to `Application Support/JustPhoto/Diagnostics/diagnostics.jsonl` (creates the file if missing).

Diagnostics location + naming (Step M1.4):
- Directory: `Application Support/JustPhoto/Diagnostics/`
- File naming: `diagnostics-YYYY-MM-DD.jsonl` (day-stamped)
- Debug helper: `PrintDiagnosticsPath` button in `justphoto_opencode/Features/Settings/DebugToolsScreen.swift`

Diagnostics size rotation (Step M1.5):
- `DiagnosticsRotationManager.rotateIfNeeded()` enforces a 50MB total cap by deleting the oldest `.jsonl` files first.
- Debug helper: `SpamDiagnostics` button in `justphoto_opencode/Features/Settings/DebugToolsScreen.swift` to generate enough logs to trigger rotation.

Diagnostics age rotation (Step M1.6):
- `DiagnosticsRotationManager.deleteOldLogs(now:maxAgeDays:)` deletes `.jsonl` files older than 30 days (based on modification date).
- Debug helpers in `justphoto_opencode/Features/Settings/DebugToolsScreen.swift`: `CreateFakeOldLogs` and `RunRotationNow`.

Diagnostics export (Step M1.7):
- Settings includes an "Export Diagnostics Logs" action in `justphoto_opencode/Features/Settings/SettingsSheet.swift`.
- Export is implemented as a single merged `.txt` artifact created by `DiagnosticsExporter.exportDiagnosticsFile()` for reliable share sheet saving.
- Sharing uses a SwiftUI wrapper `justphoto_opencode/Infrastructure/Diagnostics/ShareSheet.swift`.


Feature modules (SwiftUI-first):
- `Features/Camera/`
  - CameraScreen (UI)
  - CaptureCoordinator (pipeline orchestrator)
  - FilmstripView
  - CameraAuth + warmup state
- `Features/Viewer/`
  - ViewerContainer
  - Zoom/Pan UIKit bridge
- `Features/Settings/`
  - SettingsSheet + Debug tools
- `Features/Inspiration/`
  - InspirationSheet + ODR UI states
- `Features/Wrap/`
  - WrapScreen + template selection + export
- `Features/Paywall/`
  - PaywallSheet
- `Features/DownReasons/`
  - DownReasonsSheet

Infrastructure modules:
- `Infrastructure/Database/` (GRDB, migrations)
- `Infrastructure/Camera/` (camera permission state: `CameraAuth` mapping)
- `Infrastructure/Camera/` (warmup overlay/timeouts: `WarmupTracker`)
- `Infrastructure/Session/` (SessionRepository, models, TTL)
- `Infrastructure/Diagnostics/` (A.13 JSONL logging + export + rotation)
- `Infrastructure/Prompt/` (Prompt, PromptCenter, PromptTimings, L1/L2/L3 host views)
- `Infrastructure/Photos/` (PhotoKit write, album archiving, phantom healer)
- `Infrastructure/PoseSpec/` (loader/validator/engine runtime, scheduling, cue selection + selector debug timeline, anti-jitter gate + jitter logs)
- `Infrastructure/Files/` (pending files, cache folders)
- `Infrastructure/Network/` (NWPathMonitor wrapper)
- `Infrastructure/Purchases/` (StoreKit 2 wrapper)

Database bootstrap (Steps M1.9-M1.10):
- `justphoto_opencode/Infrastructure/Database/DatabasePaths.swift` defines the Application Support path for the SQLite file.
- `justphoto_opencode/Infrastructure/Database/DatabaseQueueFactory.swift` opens a GRDB `DatabaseQueue` for a given path.
- `justphoto_opencode/Infrastructure/Database/DatabaseMigratorFactory.swift` registers database migrations (starting with `v1`).

Database file creation (Step M1.11):
- `justphoto_opencode/Infrastructure/Database/DatabaseManager.swift` opens the database on app launch and ensures the sqlite file exists on disk.

Migration framework (Step M1.12):
- `DatabaseManager` runs migrations on startup and prints `DBMigrated:v1` on first apply, then `DBMigrationsUpToDate` on subsequent launches.

Database startup threading (Step M1.12b):
- `DatabaseManager.start()` is invoked on a background queue to avoid blocking the main runloop during file I/O and migrations.
- DebugTools exposes a `PrintDBStartMetrics` button to verify startup duration and whether it ran on the main thread.

Sessions table (Step M1.13):
- `DatabaseMigratorFactory` registers migration `v2_sessions` which creates the `sessions` table.

Session items table (Step M1.14):
- `DatabaseMigratorFactory` registers migration `v3_session_items` which creates the `session_items` table.

Ref items table (Step M1.15):
- `DatabaseMigratorFactory` registers migration `v4_ref_items` which creates the `ref_items` table.

Local stats table (Step M1.16):
- `DatabaseMigratorFactory` registers migration `v5_local_stats` which creates the `local_stats` table.

Session repository (Step M1.17):
- `justphoto_opencode/Infrastructure/Session/SessionRepository.swift` is the single read/write gateway for current session identity and lifecycle.

Session TTL (Step M1.18):
- `SessionRepository.ensureFreshSession(...)` clears and recreates the session when `now - lastActiveAt > 12h`.

Immediate flush (Step M1.19):
- `DatabaseManager.flush(reason:)` checkpoints WAL on backgrounding and after `write_failed` inserts to minimize data loss on app kill.

Prompt model (Step M2.1):
- `justphoto_opencode/Infrastructure/Prompt/Prompt.swift` defines the Prompt data model (levels, surfaces, throttle, payload) aligned with PRD Appendix A.

Prompt center (Step M2.2):
- `justphoto_opencode/Infrastructure/Prompt/PromptCenter.swift` owns the active toast/banner/modal slots and handles L3 preemption (`PromptPreempted:A->B`).

## Core Data Model (Local)

SQLite (GRDB):
- `sessions`
  - sessionId, createdAt, lastActiveAt, scene, sessionFlags
- `session_items`
  - itemId, sessionId, shotSeq (monotonic), createdAt
  - state (captured_preview/writing/write_failed/finalized), liked
  - thumbnail_state (pending/ready/failed)
  - album_state (none/adding/added/failed)
  - assetId (when available)
  - pendingFileRelPath (for recoverable writes)
  - thumbCacheRelPath (optional)
- `ref_items`
  - refId, sessionId, createdAt
  - assetId (ref copy in Photos “Just Photo” album)
  - isSelected
  - targetOutputs (numbers only; no pixels)
- `local_stats`
  - counters (local-only)

File storage:
- Pending captured files: Application Support (durable)
- Thumbnail cache: Caches (evictable)
- Diagnostics logs: Sandbox logs directory (exportable; rotated)

## Key Data Flows

### A) Photo Capture -> Save -> Filmstrip
1) User taps shutter.
2) Session immediately inserts an optimistic item (`captured_preview`) and persists.
3) When photo data arrives, app writes pending file (atomic write).
4) App writes to Photos via PhotoKit (`writing` -> `finalized` or `write_failed`).
5) On `finalized`, app verifies asset fetch (immediate + 500ms retry once).
6) App attempts album add; failures set `album_state=failed` (non-blocking) with retry policy.
7) Thumbnails replace optimistic preview; >5s -> `thumbnail_state=failed`, late success self-heals; >30s offers rebuild.

### B) Global Shutter Blocking (Data Safety)
If any session item is `write_failed`, shutter is disabled globally.
Unblock requires either:
- retry_write succeeds (item becomes finalized)
- or user abandons item (removed from workset)

### C) Live Guidance (PoseSpec)
1) Preview frames feed Vision.
2) Landmarks are normalized to portrait normalized image space.
3) PoseSpec engine computes metrics (T0/T1), selects one cue, applies anti-jitter.
4) UI shows one script card; on exit_crossed triggers praise freeze (“Now—hit the shutter”).
5) withRef mode computes target outputs from ref image; match uses exit equivalence; mirror evaluation is supported.
6) A.13 diagnostics records match state, fallback reasons, and blocked-by dimensions.

### D) Reference Images (withRef)
1) User picks ref image (from Photos or ODR).
2) App runs strong gates (multi-person, face size, eyes, shoulders). Reject if not suitable.
3) If accepted, app copies ref into Photos “Just Photo” album and stores RefItem.
4) App computes target outputs (numbers only) for withRef.
5) UI overlay shows current ref with fixed opacity/size rules.

### E) Inspiration (ODR)
1) Inspiration sheet resolves state: offline -> keywords-only; online -> ready.
2) Selecting an ODR image triggers on-demand download.
3) Download failure -> failed_retry.
4) When network recovers while in failed_retry, auto-retry once after 500ms debounce; record `odr_auto_retry`.

## Diagnostics (PRD Appendix A.13)

Mandatory local-only events:
- withref_match_state (must include blocked_by when match=false and UI is quiet)
- withref_fallback (reason + optional missing list)
- photo_write_verification (fetch verification + retry)
- phantom_asset_detected (Limited phantom)
- odr_auto_retry (state_before=failed_retry, debounce_ms=500, result)

Rotation:
- Keep logs up to 50MB total OR 30 days (whichever first). Oldest deleted first.

Export:
- Settings provides “Export diagnostics logs” via system share sheet.

## Build/Release Contracts

- PoseSpec is bundled; no remote fetch.
- `PoseSpec.prdVersion` must match PRD version (v1.1.4) or the app blocks (treat as build/release error).
- UI scene values exposed to user/logs are only `cafe|outdoor` (internal base scene must not leak as a UI scene).
