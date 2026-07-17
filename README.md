# GPS Tracker

A fully offline, 24/7 background-running, battery-efficient GPS tracker for
iOS 18+ (Swift 6, SwiftUI). All data stays on the device: **zero network
requests, no analytics, no telemetry, no accounts, no sync.**

## Project layout

| Path | Purpose |
| --- | --- |
| `GPSTracker.xcodeproj` | iOS app project (iOS 18.0, Swift 6 language mode, iPhone) |
| `GPSTracker/` | App sources: services, persistence, SwiftUI UI |
| `TrackerKit/` | Local Swift package with all pure logic — fixed-point codecs, Douglas-Peucker, GPX/GeoJSON/CSV exporters, SQL schema, energy-policy state machine. No Apple-only APIs, unit-tested on any platform (including Linux CI) |

Dependencies: [GRDB.swift](https://github.com/groue/GRDB.swift) (SQLite toolkit,
fetched by Xcode via SPM) and the local `TrackerKit` package. Nothing else.

## Architecture

```
UI (SwiftUI tabs: Live map / History / Settings)
        │
RecordingCoordinator (@MainActor, @Observable)   ← central state machine
   │            │              │
LocationService MotionActivity EnergyPolicy (pure, in TrackerKit)
(CLLocationMgr) (CMMotionAct.)  activity+speed → tracking mode
        │
PersistenceStore (actor, GRDB, WAL, batched writes)
        │
ExportEngine → GPX 1.1 / GeoJSON / CSV → share sheet
```

### Adaptive energy model

| Mode | Trigger | GPS configuration | Est. battery |
| --- | --- | --- | --- |
| Stationary | ≥3 min of high-confidence stationary evidence | GPS **off**; significant-change monitoring + 150 m `CLMonitor` geofence for wakeups | ~0.1 %/h |
| Moving (default) | walking/running/cycling/driving, or speed ≥ 0.5 m/s | `kCLLocationAccuracyHundredMeters`, 75 m distance filter | ~0.9 %/h |
| Precise (opt-in) | Settings toggle | `kCLLocationAccuracyBest`, 10 m filter | ~3 %/h |

A typical day (20 h stationary + 4 h moving) estimates ≈ 5.6 %/24 h, inside the
5–8 % target. Best-accuracy GPS is never the default.

### Background lifecycle

- `allowsBackgroundLocationUpdates = true`, `pausesLocationUpdatesAutomatically = false`,
  `UIBackgroundModes = [location]`.
- Permission flow: When-In-Use requested first; the Always upgrade is a separate,
  explained step (banner on the map tab).
- Significant-change monitoring stays active for the entire recording, so the
  system relaunches the app after termination or reboot. `AppDelegate`
  checks `launchOptions[.location]` and resumes recording (mode restored from
  `UserDefaults`) before any UI is built.

### Data layer

- Single SQLite file (GRDB `DatabasePool` → WAL mode), `Application Support/Database/tracker.sqlite`.
- Point payload: `ts Int32`, `lat/lon Int32` (fixed-point 1e-7°), `alt/speed/course/hAcc Int16`,
  `activity UInt8` = 21 bytes of fields; ~30–35 bytes/row on disk with SQLite
  overhead. 350k points (a year at 1 fix/30 s for 8 h/day) ≈ **12 MB**, well under 50 MB.
- Writes are buffered (20 points / 30 s) and flushed in single transactions; extra
  flushes on backgrounding and when entering stationary mode.
- Background Douglas-Peucker pass writes per-day simplified tracks into a separate
  table; raw data is never modified.
- Retention setting auto-deletes old points (`incremental_vacuum` reclaims space).

### Privacy

- `NSFileProtectionCompleteUntilFirstUserAuthentication` on the database
  (plus the data-protection entitlement).
- Optional Face ID / passcode lock (LocalAuthentication, `.deviceOwnerAuthentication`).
- Optional `isExcludedFromBackup` on the database and its WAL/SHM sidecars.
- Honest Info.plist purpose strings; no third-party SDKs of any kind.

## Building

Open `GPSTracker.xcodeproj` in Xcode 16+ (iOS 18 SDK), let SPM resolve GRDB,
select your team for automatic signing, and run on a device. Location and
motion behavior cannot be meaningfully tested in the simulator.

## Running the tests

All pure logic is tested in `TrackerKit` (61 tests: fixed-point codecs,
Douglas-Peucker, GPX/GeoJSON/CSV golden outputs, schema migrations against a
real SQLite, energy-policy transitions):

```sh
cd TrackerKit
swift test
```

Works on macOS and Linux (Linux needs `libsqlite3-dev` for the migration tests).
The GPX output has been validated against the official GPX 1.1 XSD with
`xmllint --schema`.

## On-device verification checklist

These acceptance criteria require real hardware:

1. **Locked-screen recording** — start recording, lock the phone, walk ≥500 m:
   the track must be continuous afterwards (blue background-location indicator
   visible in the status bar / Dynamic Island).
2. **Termination resume** — start recording, force-quit the app, drive/walk
   ≥1 km: iOS relaunches the app for the significant-change event and recording
   resumes (points appear for the period after the kill). Repeat with a reboot.
3. **Battery** — with Always permission and default (non-precise) mode, record
   for 24 h of typical use; check Settings → Battery: the app should account
   for ≤5–8 %. Verify GPS turns off when stationary (mode label in the
   recording pill switches to "stationary, GPS off" after ~3 min at rest).
4. **Zero network** — run the device through a proxy (Charles/mitmproxy) or
   Instruments' Network template: the app must originate no connections.
   (MapKit's tile fetches are performed by Apple's separate `geod` daemon, not
   by the app process; disable the map tab check by putting the phone in
   airplane mode if your proxy attributes system traffic ambiguously.)
5. **Import** — export a GPX date range and import it into Dawarich or
   AdventureLog; times are UTC ISO-8601, coordinates 7-decimal fixed-point.

## Design notes

- `LocationService` runs on the main actor because `CLLocationManager`
  requires a run loop for delegate delivery; the callback rate is at most a
  few per minute. All storage IO happens in the `PersistenceStore` actor.
- `EnergyPolicy` is a pure value type in TrackerKit so every mode transition
  (debounce, wake-on-speed, low-confidence rejection) is unit-tested.
- `CMMotionActivityManager` only reports *changes*; a 60 s timer re-feeds the
  last evidence so the stationary debounce can elapse. If motion data is
  denied, a 5-minute no-fix fallback still turns GPS off when parked.
