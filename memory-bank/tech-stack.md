# Tech Stack (MVP) — Just Photo (iOS 16+)

Goal: ship a robust MVP fast. Prefer mature Apple APIs + a tiny set of well-known, well-documented libraries. No “architecture for architecture’s sake”.

## Recommendation (Simple + Robust)

- Platform: Native iOS only (iOS 16+)
- Language: Swift
- UI: SwiftUI for most screens + UIKit bridging only where it matters (camera preview + advanced gestures)
- Core engines: AVFoundation (camera), Vision (on-device detection), PhotoKit (save/limited access)
- Local-only data: SQLite via GRDB
- Purchases: StoreKit 2
- ODR: On-Demand Resources (NSBundleResourceRequest)

Why not cross-platform (Flutter / React Native) for this PRD:
- Your P0 requirements are camera/perf/PhotoKit/permissions/state-machine heavy; cross-platform pushes the hardest parts into custom native bridging and makes performance + QA acceptance harder.

## Core Modules and What We Use

### 1) Camera & Capture

- API: `AVFoundation`
  - `AVCaptureSession` + `AVCapturePhotoOutput` for photo capture
  - `AVCaptureVideoDataOutput` for low-latency preview frames (for Vision + ROI metrics)
  - Preview: `AVCaptureVideoPreviewLayer`

Implementation notes (MVP-safe):
- Put capture + save pipeline behind a single coordinator (one place to enforce: in-flight<=2, write_failed global block, session 20 limit).
- Use Swift Concurrency (Task/actor) to keep the UI responsive.

### 2) On-device Detection (Pose/Face)

- API: `Vision`
  - Face landmarks / bounding box
  - Human body pose landmarks

PoseSpec usage (Glue-first):
- Treat `PoseSpec.json` as the data source for: thresholds, priorities, scripts, binding aliases, ROI definitions, antiJitter settings, withRef exit rules.
- Do NOT build a fully generic “formula language runtime” for MVP.
  - Implement a small, explicit set of metrics in Swift (the ones PoseSpec actually needs).
  - This keeps performance predictable and QA reproducible.

Optional (only if you truly need data-driven formulas later):
- Add a lightweight expression evaluator library; otherwise keep formulas compiled into code.

### 3) Photos Save, Album, and Permissions (Data Safety)

- API: `Photos / PhotoKit`
  - `PHPhotoLibrary` write
  - `PHAsset` fetch by localIdentifier
  - Limited access support + “phantom asset” handling
  - Album add (`Just Photo` album) with retry policy

PRD-specific reliability hooks:
- After `write_success`, do Asset Fetch Verification Retry (e.g. 500ms x1) to handle PhotoKit indexing delay.
- Model save states explicitly (`captured_preview`, `writing`, `write_success`, `write_failed`, `thumb_ready`, `thumb_failed`, `album_add_failed`, ...).

### 4) Viewer & Gestures

- UI: SwiftUI shell
- Gestures: `UIScrollView`-based zoom/pan wrapped via `UIViewRepresentable`
  - Makes it easy to implement “scale<=1.01 treated as 1” and “pinch wins over swipe”.

### 5) Wrap / Collage Export

- API: `UIGraphicsImageRenderer` (CoreGraphics)
  - Deterministic output size: 1080x1920
  - Center-crop per cell
- Save/export: PhotoKit + `UIActivityViewController`

### 6) ODR Inspiration Library

- API: On-Demand Resources
  - `NSBundleResourceRequest`
- Network status: `Network.framework` (`NWPathMonitor`)
  - Implement PRD rule: when state is `failed_retry` and network recovers, debounce 500ms then auto-retry once.

### 7) Subscription / Paywall

- API: `StoreKit 2`
  - Products: monthly/yearly (+ trial)
  - Restore purchases
  - “Manage subscription” deep link (system)

### 8) Local Storage (You Chose Local-Only)

Recommended:
- Database: SQLite
- Library: `GRDB` (Swift)

What to store:
- Session/workset index (items + states)
- Reference images metadata (identifiers, targets, per-session limits)
- Local-only stats counters
- Diagnostic log index (log files are still file-based; DB stores pointers/metadata if needed)

Why GRDB (Glue Coding):
- Mature, well-documented, widely used, easy for AI/codegen help, and avoids inventing persistence.

### 9) Logging & Diagnostics (Local-only)

- API: `OSLog` for runtime logs + a simple file logger for export
- File policy: rolling logs, max 30 days or 50MB (whichever first)
- Export: `UIActivityViewController`

Keep it simple:
- One JSON-lines file format (one event per line) so it is easy to parse, grep, and share.

## Minimal Third-Party Dependencies

Required:
- `GRDB` (SQLite persistence)

Optional (add only if needed by performance/UX, not by taste):
- `Nuke` for image decoding/caching if PhotoKit caching is insufficient in Viewer
- `SnapshotTesting` (pointfreeco) if you want fast UI regression checks

Dependency manager:
- Swift Package Manager (SPM) only

## Testing (MVP Practical)

- Unit tests: `XCTest`
- Performance: `XCTMetric` (measure camera ready time, viewer first frame, thumbnail latency)
- Small deterministic QA asset harness for PoseSpec before/after images (as per PoseSpec naming convention)

## What We Intentionally Avoid (MVP)

- Cross-platform frameworks (adds native-bridge complexity for camera + PhotoKit)
- Heavy app architectures (Redux/TCA/Clean/hexagonal) unless the team already uses them
- Remote backends/analytics SDKs (PRD says local-only)
- A generic expression compiler/runtime for PoseSpec formulas (do only if it becomes a proven bottleneck)
