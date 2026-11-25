# CLAUDE.md — Rak-tracker (GPSTracker)

## What this is
iOS 18+ / Swift 6 / SwiftUI, **fully offline** GPS recording app. The detailed architecture is in `README.md`.

| Path | Purpose |
|---|---|
| `GPSTracker.xcodeproj` | iOS app project (iPhone, Swift 6 language mode) |
| `GPSTracker/` | App: `Services`, `Persistence`, `UI`, `App`, `Resources` |
| `TrackerKit/` | Local Swift package — pure logic: fixed-point codecs, Douglas-Peucker, GPX/GeoJSON/CSV export, SQL schema, energy-policy state machine |

Dependencies: GRDB.swift (SPM) + local `TrackerKit`. Nothing else.

Flow: `RecordingCoordinator` (@MainActor, @Observable) → `LocationService` / `CMMotionActivity` / `EnergyPolicy` → `PersistenceStore` (actor, GRDB, WAL, batched writes) → `ExportEngine`.

## Commands
```bash
(cd TrackerKit && swift test)    # pure logic — 61 tests; subshell, so you stay in the repo root
xcodebuild build -project GPSTracker.xcodeproj -scheme GPSTracker -configuration Debug \
  -destination 'generic/platform=iOS' -derivedDataPath "${TMPDIR:-/tmp}/GPSTracker-DerivedData" \
  CODE_SIGNING_ALLOWED=NO
```

The app target builds with Xcode 27.0 (2026-09-30: `BUILD SUCCEEDED`, ~23 s, 0 compiler warnings). The simulator runtime is not installed, so the destination is `generic/platform=iOS` and the build is unsigned; running it and testing its behavior require a real device (see the checklist in the README). Resolving the GRDB package for the first time needs network access (outside the sandbox).

## Important
- **Zero network requests, no analytics, no accounts, no sync.** This is a product decision. Never add a network call, SDK, telemetry, or crash reporter without asking.
- Location data is personal: don't put sample coordinate/track output in reports or artifacts.
- New pure logic goes into `TrackerKit` (it uses no Apple-specific APIs and can be tested on Linux too); only code that needs iOS APIs goes into `GPSTracker/`.
- Remote: `ResulKarahasanMD/Rak-tracker`; active branch: `RAK-MD`. No commits or pushes without permission.
