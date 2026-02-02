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

3) Save Pipeline & Photos Integration (PhotoKit)
- Writes captured photos to system Photos.
- After `write_success`, runs Asset Fetch Verification Retry (immediate fetch, then 500ms retry once).
- Adds assets to the “Just Photo” album; failures produce `album_add_failed` (non-blocking) and support retries.
- Limited Access support includes phantom asset healing and `phantom_asset_detected` diagnostics.

Project-level configuration notes:
- This project uses Xcode-generated Info.plist (`GENERATE_INFOPLIST_FILE=YES`). Privacy strings are set via build settings `INFOPLIST_KEY_*` in `justphoto_opencode.xcodeproj/project.pbxproj`.
- Step M0.4 adds the required usage descriptions: Camera, Photo Library (read), Photo Library (add).

4) Session System (Business Session; not AVCaptureSession)
- A “Session” is a local workset (max 20) that drives filmstrip/viewer/wrap.
- Persistence is via SQLite (GRDB) plus file-based caches for pending writes and thumbnails.
- Must survive kill/relaunch with recoverable `write_failed` items.

5) PoseSpec Engine (Vision + PoseSpec.json)
- Reads PoseSpec from the app bundle, validates contracts (binding/rois/prdVersion), and evaluates cues.
- Runs a tiered scheduler: T0 (pose/face geometry) up to 15Hz; T1 (ROI/frame metrics) up to 2Hz.
- Provides: single cue selection, anti-jitter, praise policy, withRef matching (including mirror evaluation).
- Emits A.13 diagnostics events for match state, fallbacks, and related invariants.

6) Prompt System (L1/L2/L3)
- Centralized, contract-driven prompt presenter (Toast/Banner/Modal) with mutual exclusion and throttling.
- Logs prompt show/dismiss/action locally (A.12 recommended, local only).
- VoiceOver changes toast/banner timing (no in-app TTS).

Debug-only UI policy:
- Debug Tools UI is guarded by `#if DEBUG` in `justphoto_opencode/Features/Settings/SettingsSheet.swift` and `justphoto_opencode/Features/Settings/DebugToolsScreen.swift`.
- Project build settings explicitly prevent `DEBUG` from being defined in Release (see `SWIFT_ACTIVE_COMPILATION_CONDITIONS` in `justphoto_opencode.xcodeproj/project.pbxproj`).

Debug Tools currently include:
- A `DebugToolsPing` button in `justphoto_opencode/Features/Settings/DebugToolsScreen.swift` that prints `DebugToolsPing` to Xcode console for quick plumbing verification.

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
- `Infrastructure/Session/` (SessionRepository, models, TTL)
- `Infrastructure/Diagnostics/` (A.13 JSONL logging + export + rotation)
- `Infrastructure/Prompt/` (PromptCenter, L1/L2/L3)
- `Infrastructure/Photos/` (PhotoKit write, album archiving, phantom healer)
- `Infrastructure/PoseSpec/` (loader/validator/engine runtime, scheduling)
- `Infrastructure/Files/` (pending files, cache folders)
- `Infrastructure/Network/` (NWPathMonitor wrapper)
- `Infrastructure/Purchases/` (StoreKit 2 wrapper)

## Core Data Model (Local)

SQLite (GRDB):
- `sessions`
  - sessionId, createdAt, lastActiveAt, scene, sessionFlags
- `session_items`
  - itemId, sessionId, shotSeq (monotonic), createdAt
  - state (captured_preview/writing/write_success/write_failed/album_add_* /thumb_*), liked
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
4) App writes to Photos via PhotoKit (`writing` -> `write_success` or `write_failed`).
5) On `write_success`, app verifies asset fetch (immediate + 500ms retry once).
6) App attempts album add; failures become `album_add_failed` (non-blocking) with retry policy.
7) Thumbnails replace optimistic preview; >5s -> `thumb_failed`, late success self-heals; >30s offers rebuild.

### B) Global Shutter Blocking (Data Safety)
If any session item is `write_failed`, shutter is disabled globally.
Unblock requires either:
- retry_write succeeds (item becomes write_success)
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
