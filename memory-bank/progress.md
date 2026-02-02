# Progress

Rule: Each checkpoint is either `[ ]` (not done) or `[x]` (done). Update immediately after completing a checkpoint.

## Milestone 0 — Project Skeleton (Runs + Navigates + Debug Hooks)

- [x] M0.1 Create Xcode project (iOS 16+, Swift)
- [x] M0.2 Create top-level folder/groups in Xcode
- [x] M0.3 Create empty screen files (no logic)
- [x] M0.4 Add Info.plist permission strings
- [x] M0.5 Add Debug Tools entry (Debug build only)
- [x] M0.6 Add “DebugToolsPing” button

## Milestone 1 — Diagnostics Log (A.13) + GRDB + SessionStore Base (Recoverable)

### 1A. Diagnostics Log (PRD A.13)

- [x] M1.1 Create diagnostics module files
- [ ] M1.2 Define mandatory JSONL record fields (A.13)
- [ ] M1.3 Implement “append one JSON line”
- [ ] M1.4 Implement log file location and naming
- [ ] M1.5 Implement rotation by total size (50MB)
- [ ] M1.6 Implement rotation by age (30 days)
- [ ] M1.7 Implement Settings “Export Diagnostics Logs”
- [ ] M1.8 Add A.13 required events (just the ability to write them)

### 1B. GRDB (third-party) + DB bootstrap

- [ ] M1.9 Add GRDB via Swift Package Manager
- [ ] M1.10 Create DB bootstrap files
- [ ] M1.11 Create DB file on first launch
- [ ] M1.12 Add migration framework (v1)

### 1C. SessionStore (PRD Appendix B) minimal persistence + TTL

- [ ] M1.13 Create tables (sessions)
- [ ] M1.14 Create tables (session_items)
- [ ] M1.15 Create tables (ref_items)
- [ ] M1.16 Create tables (local_stats)
- [ ] M1.17 Create SessionRepository (single read/write gateway)
- [ ] M1.18 Implement session TTL = 12h (B.3.4)
- [ ] M1.19 Implement immediate flush on critical moments (B.3.1)

## Milestone 2 — Prompt System (L1/L2/L3 + Mutual Exclusion + VoiceOver Timings + Local prompt logs)

- [ ] M2.1 Create Prompt model file
- [ ] M2.2 Create PromptCenter (single controller)
- [ ] M2.3 Implement L1 Toast slot
- [ ] M2.4 Implement L2 Banner slot
- [ ] M2.5 Implement L3 Modal slot
- [ ] M2.6 Implement VoiceOver timing switch (VOICEOVER_*)
- [ ] M2.7 Log prompt events locally (A.12)

## Milestone 3 — Camera Permission State Machine + Warmup Timeouts (P0)

- [ ] M3.1 Create CameraAuth module (AVAuthorizationStatus mapping)
- [ ] M3.2 Implement not_determined pre-prompt (PRD 4.1.2)
- [ ] M3.3 Wire Continue to trigger system camera permission dialog
- [ ] M3.4 Implement denied/restricted UI
- [ ] M3.5 Create WarmupState tracker (3s upgrade, 8s fail)
- [ ] M3.6 Define CameraInitFailureReason enum and mapping
- [ ] M3.7 Implement “Retry camera init”

## Milestone 4 — Capture + Save State Machine (P0 Data Safety) + Pending Recovery

### 4A. Rules & Counters

- [ ] M4.1 Create WorksetCounter utility
- [ ] M4.2 Create SessionRuleGate module (single source for shutter enable)
- [ ] M4.3 Implement 15-count banner gate (14->15, sessionOnce)
- [ ] M4.4 Implement 20-limit modal + shutter disabled persists after cancel

### 4B. Capture pipeline (optimistic -> pending file -> PhotoKit write)

- [ ] M4.5 Create CaptureCoordinator file (single pipeline owner)
- [ ] M4.6 Create SessionItemState definition aligned with PRD
- [ ] M4.7 Implement shutter tap gate checks (no capture when blocked)
- [ ] M4.8 Create optimistic item immediately
- [ ] M4.9 Create PendingFileStore module (Application Support/pending)
- [ ] M4.10 Write photo data to pending within 2s or convert to capture_failed
- [ ] M4.11 Start PhotoKit write only after pending file exists

### 4C. Asset Fetch Verification Retry (v1.1.4)

- [ ] M4.12 Implement immediate fetch verification after write_success
- [ ] M4.13 Implement 500ms×1 retry if first fetch fails

### 4D. write_failed global block (A.11) + Viewer handling

- [ ] M4.14 Define write_failed reasons enum list (PRD A.10)
- [ ] M4.15 On write_failed: force immediate DB flush
- [ ] M4.16 On write_failed: block shutter and show L3 on Camera
- [ ] M4.17 Implement Viewer “retry save”
- [ ] M4.18 Implement Viewer “abandon item”

### 4E. capture_failed counter window (30s / 3 times -> L3)

- [ ] M4.19 Create CaptureFailureTracker module

### 4F. Thumbnails: thumb_failed + self-heal + rebuild

- [ ] M4.20 Create ThumbnailPipeline module
- [ ] M4.21 Implement 5s threshold to mark thumb_failed
- [ ] M4.22 Implement late self-heal (thumb_failed -> thumb_ready)
- [ ] M4.23 Implement 30s permanent failure + “Rebuild thumbnail”

### 4G. Album archiving: album_add_failed non-blocking + retry policy

- [ ] M4.24 Create AlbumArchiver module (PhotoKit album add)
- [ ] M4.25 Implement album_add_failed state + first-session banner
- [ ] M4.26 Implement “修复” bulk retry
- [ ] M4.27 Implement automatic retry backoff (1s/3s/10s, max 3)
- [ ] M4.28 Implement “retry once on next launch”

### 4H. Limited phantom asset handling + required diagnostics (v1.1.4)

- [ ] M4.29 Create PhantomAssetHealer module
- [ ] M4.30 Write `phantom_asset_detected` (A.13)

## Milestone 5 — Filmstrip + Viewer + Liked (Local-only) + Favorite Sync Attempt

- [ ] M5.1 Create Filmstrip component file
- [ ] M5.2 Implement “newest first” ordering everywhere
- [ ] M5.3 Implement state badges mapping (saving / ! / normal)
- [ ] M5.4 Create ViewerContainer file (x/y, close, like)
- [ ] M5.5 Create Zoom/Pan UIKit bridge file
- [ ] M5.6 Implement scale<=1.01 treated as 1 (PRD)
- [ ] M5.7 Implement “pinch wins over swipe”
- [ ] M5.8 Persist liked in DB (GRDB usage)
- [ ] M5.9 Attempt sync to system Favorites (Full access only; failure non-blocking)

## Milestone 6 — PoseSpec Engine (Bundle-only, Deterministic, A.13 Diagnostics)

- [ ] M6.1 Add PoseSpec.json to app bundle resources
- [ ] M6.2 Create PoseSpecLoader file
- [ ] M6.3 Create PoseSpecValidator file (required fields)
- [ ] M6.4 Enforce prdVersion match (PRD 4.4.1)
- [ ] M6.5 Validate binding.aliases minimal set (PRD 4.4.2)
- [ ] M6.6 Validate rois dictionary (PRD 4.4.3)
- [ ] M6.7 Implement “portrait normalized” coordinate normalization (PoseSpec.coordinateSystem)
- [ ] M6.8 Create VisionPipeline files (pose + face)
- [ ] M6.9 Create ROIComputer file (faceROI/eyeROI/bgROI)
- [ ] M6.10 Create MetricComputer file (only metrics needed by PoseSpec v1.1.4)
- [ ] M6.11 Create TierScheduler file (T0 15Hz / T1 2Hz)
- [ ] M6.12 Create CueEvaluator file (enter/warn/hard/exit)
- [ ] M6.13 Create CueSelector file (priority+severity+mutex per PoseSpec.defaults.selection)
- [ ] M6.14 Create AntiJitterGate file (persistFrames/minHoldMs/cooldownMs)
- [ ] M6.15 Create PraiseController file (PoseSpec.praisePolicy)
- [ ] M6.16 Create RefTargetExtractor file (compute target outputs from ref image)
- [ ] M6.17 Store RefTarget in session-scoped storage (and clear on reset)
- [ ] M6.18 Create MirrorEvaluator (x=0.5)
- [ ] M6.19 Create MatchDecider = “PoseSpec exit equivalence” (PRD 5.1.1.a)
- [ ] M6.20 Emit `withref_match_state` (A.13)
- [ ] M6.21 Emit `withref_fallback` (A.13)

## Milestone 7 — Reference Images (Import, Gates, Copy-to-Album, Overlay, Limits)

- [ ] M7.1 Create RefItem model file (DB-backed)
- [ ] M7.2 Create ReferencePicker module (user photo picker)
- [ ] M7.3 Implement “first ref save notice” installOnce prompt (PRD 5.2)
- [ ] M7.4 Create RefGateEvaluator file (strong thresholds 5.2.1)
- [ ] M7.5 Multi-person gate (>=2 faces with confidence>=0.6)
- [ ] M7.6 Face too small gate (areaRatio<0.02 OR widthRatio<0.12)
- [ ] M7.7 Eyes not visible gate (either eye conf<0.5)
- [ ] M7.8 Upper body incomplete gate (either shoulder conf<0.5)
- [ ] M7.9 Rejection prompt + copy does not proceed
- [ ] M7.10 On accept: copy ref to system “Just Photo” album (PRD 5.2)
- [ ] M7.11 Ref copies limit = 10 per session
- [ ] M7.12 Create ReferenceOverlay UI files
- [ ] M7.13 Enforce drag clamp + cannot cover shutter button
- [ ] M7.14 Prev/Next switching among refs
- [ ] M7.15 Reset session clears ref list + target outputs

## Milestone 8 — Inspiration Sheet (ODR + Offline Keywords + Auto Retry)

- [ ] M8.1 Create InspirationState enum file (4 states)
- [ ] M8.2 Create KeywordCatalog file (local keywords by scene)
- [ ] M8.3 Create ODRManager module
- [ ] M8.4 Implement “tap image => request tag download”
- [ ] M8.5 Implement failed_retry state (with retry button)
- [ ] M8.6 Implement offline_keywords_only state when no network
- [ ] M8.7 Implement auto retry on network recovery (debounce 500ms, once per recovery)
- [ ] M8.8 Emit `odr_auto_retry` (A.13)

## Milestone 9 — Wrap/Collage (1×3, 2×2, Export, Fail States)

- [ ] M9.1 Create WrapEntryRule module
- [ ] M9.2 Create WrapState model file (selected template + selected items)
- [ ] M9.3 Implement default selection rule
- [ ] M9.4 Implement template switcher (only 1×3 and 2×2)
- [ ] M9.5 Implement “tap slot -> open bottom picker -> replace”
- [ ] M9.6 Create CollageRenderer module (fixed 1080×1920, center-crop)
- [ ] M9.7 Save collage to Photos (PhotoKit)
- [ ] M9.8 Share sheet flow (user cancel is not an error)
- [ ] M9.9 Fail states: permission denied
- [ ] M9.10 Fail states: low storage
- [ ] M9.11 Fail states: render failure

## Milestone 10 — Settings (Permissions, Import, Gridlines, Logs, Pro Entry)

- [ ] M10.1 Create SettingsState storage keys (GRDB usage)
- [ ] M10.2 Implement gridlines overlay in Camera preview
- [ ] M10.3 Add “Manage Selected Photos” (Limited Picker) entry
- [ ] M10.4 Add “Open System Settings” entry
- [ ] M10.5 Add “Import Photos to Session” entry
- [ ] M10.6 Enforce 20 limit during import
- [ ] M10.7 Wire “Export Diagnostics Logs” in Settings (from Milestone 1)
- [ ] M10.8 Add Pro card entry to open Paywall

## Milestone 11 — Paywall + StoreKit 2 (Purchase, Restore, Failure Prompts, Expiry Downgrade)

- [ ] M11.1 Create StoreKitManager module
- [ ] M11.2 Implement “current entitlement status” display
- [ ] M11.3 Implement purchase flow (success path)
- [ ] M11.4 Implement restore flow (success path)
- [ ] M11.5 Implement purchase failure L3 (PRD)
- [ ] M11.6 Implement restore failure L3 (PRD)
- [ ] M11.7 Implement expiry downgrade rules (PRD E4)

## Milestone 12 — Down Reasons Sheet (Local-only, >=10 shows)

- [ ] M12.1 Add entry visibility rule (>=10 photos)
- [ ] M12.2 Create DownReasons catalog file
- [ ] M12.3 Implement selection (single-select MVP)
- [ ] M12.4 Log selection locally (diagnostics)

## Milestone 13 — Performance SLO + QA Regression Hooks (Local-only)

- [ ] M13.1 Add camera-ready timer (PRD 4.1.1)
- [ ] M13.2 Record thumb replacement latency (shutter -> thumb_ready)
- [ ] M13.3 Record viewer first-frame latency
- [ ] M13.4 Implement thermal / dropped-frames degrade rules (PRD 4.4.6)
- [ ] M13.5 QA asset harness entry (PoseSpec.qaAssets naming convention)
- [ ] M13.6 A.13 acceptance checks (must be demonstrable)

## Final MVP “No Remote Data” Audit

- [ ] F.1 Dependency audit
- [ ] F.2 PRD QA checklist run (Section 10)
