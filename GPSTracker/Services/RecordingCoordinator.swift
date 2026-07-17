import CoreLocation
import Foundation
import Observation
import TrackerKit
import UIKit

/// Central state machine of the app: wires location fixes and motion-activity
/// evidence into `EnergyPolicy`, applies the resulting mode to the GPS radio,
/// and forwards recorded points to the persistence actor.
@MainActor
@Observable
final class RecordingCoordinator {
    // MARK: Observable state (drives the UI)

    private(set) var isRecording = false
    private(set) var mode: TrackingMode = .moving
    private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined
    private(set) var lastLocation: CLLocation?
    private(set) var currentActivity: ActivityFlag = .unknown
    /// Today's recorded path, for the live map polyline.
    private(set) var livePathCoordinates: [CLLocationCoordinate2D] = []
    private(set) var sessionPointCount = 0

    var preciseModeEnabled: Bool {
        get { policy.preciseEnabled }
        set {
            policy.preciseEnabled = newValue
            UserDefaults.standard.set(newValue, forKey: SettingsKeys.preciseModeEnabled)
            applyCurrentMode()
        }
    }

    /// Rough battery impact of the current state, for the UI.
    var estimatedPercentPerHour: Double {
        isRecording ? BatteryEstimator.percentPerHour(for: mode) : 0
    }

    // MARK: Dependencies

    let store: PersistenceStore
    private let location: LocationService
    private let motion: MotionActivityService
    private var policy: EnergyPolicy

    /// Fixes worse than this are noise and never stored.
    private let maximumAcceptedHorizontalAccuracy: CLLocationAccuracy = 200

    /// CMMotionActivityManager only reports activity *changes*, but the
    /// stationary debounce needs continuous evidence over time. While
    /// recording (and not already stationary), this timer re-feeds the last
    /// known evidence every minute so the debounce can actually elapse.
    /// While the app is suspended in stationary mode it never fires — by
    /// then GPS is already off, which is the goal.
    private var evidenceTimer: Timer?
    private let evidenceRefreshInterval: TimeInterval = 60
    /// No fix for this long in moving mode (with a 75 m distance filter)
    /// means no displacement: treated as stationary evidence even when
    /// motion-activity data is unavailable or denied.
    private let noFixStationaryFallbackSeconds: TimeInterval = 300
    private var lastFixDate: Date?

    init(store: PersistenceStore = .shared) {
        self.store = store
        self.location = LocationService()
        self.motion = MotionActivityService()
        self.policy = EnergyPolicy()
        self.policy.preciseEnabled = UserDefaults.standard.bool(forKey: SettingsKeys.preciseModeEnabled)
        self.authorizationStatus = location.authorizationStatus

        location.onLocations = { [weak self] locations in
            self?.handle(locations: locations)
        }
        location.onStationaryFenceExit = { [weak self] in
            self?.noteMovementWakeup()
        }
        location.onAuthorizationChange = { [weak self] status in
            self?.authorizationStatus = status
        }
        motion.onEvidence = { [weak self] evidence in
            self?.process(evidence: evidence)
        }
    }

    // MARK: - Launch / relaunch

    /// Called from `application(_:didFinishLaunchingWithOptions:)`.
    ///
    /// When the system relaunches the app for a location event (significant
    /// change after termination, or after reboot), recording is resumed
    /// immediately — before any UI exists — so no queued fixes are lost.
    func handleLaunch(launchedForLocationEvent: Bool) {
        let wasRecording = UserDefaults.standard.bool(forKey: SettingsKeys.recordingActive)
        guard wasRecording else { return }
        guard authorizationStatus == .authorizedAlways || authorizationStatus == .authorizedWhenInUse else { return }

        if let stored = UserDefaults.standard.string(forKey: SettingsKeys.lastTrackingMode),
           let storedMode = TrackingMode(rawValue: stored) {
            mode = storedMode
        }
        _ = launchedForLocationEvent // resume in both cases; the flag is informational
        beginRecordingSession(resuming: true)
    }

    /// Housekeeping performed once per foreground activation.
    func performMaintenance() {
        let retentionDays = UserDefaults.standard.integer(forKey: SettingsKeys.retentionDays)
        Task.detached(priority: .utility) { [store] in
            if retentionDays > 0 {
                try? await store.deletePoints(olderThanDays: retentionDays)
            }
            try? await store.simplifyCompletedDays()
        }
    }

    /// Flush buffered points when the app is about to lose execution time.
    /// Wrapped in a UIKit background task so the write can finish even if
    /// the app is being suspended (e.g. recording was just stopped).
    func flushSoon() {
        let taskID = UIApplication.shared.beginBackgroundTask(withName: "FlushTrackPoints")
        Task { [store] in
            await store.flush()
            if taskID != .invalid {
                UIApplication.shared.endBackgroundTask(taskID)
            }
        }
    }

    // MARK: - Permission flow

    /// When-In-Use first; the Always upgrade is a separate explicit step.
    func requestInitialPermission() {
        location.requestWhenInUseAuthorization()
    }

    func requestAlwaysUpgrade() {
        location.requestAlwaysAuthorization()
    }

    var needsAlwaysUpgrade: Bool {
        authorizationStatus == .authorizedWhenInUse
    }

    // MARK: - Recording control

    func startRecording() {
        guard !isRecording else { return }
        switch authorizationStatus {
        case .notDetermined:
            requestInitialPermission()
            return
        case .denied, .restricted:
            return
        default:
            break
        }
        mode = policy.mode
        beginRecordingSession(resuming: false)
    }

    func stopRecording() {
        guard isRecording else { return }
        isRecording = false
        UserDefaults.standard.set(false, forKey: SettingsKeys.recordingActive)
        evidenceTimer?.invalidate()
        evidenceTimer = nil
        location.stopRecording()
        motion.stop()
        flushSoon()
    }

    private func beginRecordingSession(resuming: Bool) {
        isRecording = true
        UserDefaults.standard.set(true, forKey: SettingsKeys.recordingActive)
        if !resuming {
            policy = EnergyPolicy()
            policy.preciseEnabled = UserDefaults.standard.bool(forKey: SettingsKeys.preciseModeEnabled)
            mode = policy.mode
            sessionPointCount = 0
        } else if policy.preciseEnabled {
            mode = .precise
        }
        persistMode()
        location.startRecording(profile: EnergyPolicy.profile(for: mode))
        motion.start()
        startEvidenceTimer()
    }

    private func startEvidenceTimer() {
        evidenceTimer?.invalidate()
        let timer = Timer(timeInterval: evidenceRefreshInterval, repeats: true) { [weak self] _ in
            // Scheduled on the main run loop, so this fires on the main thread.
            MainActor.assumeIsolated {
                self?.refreshEvidence()
            }
        }
        timer.tolerance = evidenceRefreshInterval / 4
        RunLoop.main.add(timer, forMode: .common)
        evidenceTimer = timer
    }

    /// Re-evaluates the energy policy with the freshest evidence available.
    private func refreshEvidence() {
        guard isRecording, mode != .stationary else { return }
        let now = Date().timeIntervalSince1970

        if var last = motion.lastEvidence {
            last.timestamp = now
            process(evidence: last)
            if mode == .stationary { return }
        }

        // Fallback for missing/denied motion data: prolonged silence from a
        // distance-filtered GPS means the device has not moved.
        if let lastFix = lastFixDate,
           Date().timeIntervalSince(lastFix) >= noFixStationaryFallbackSeconds {
            process(evidence: EnergyPolicy.Evidence(
                activity: .stationary, confidence: .high, speedMps: nil, timestamp: now
            ))
        }
    }

    // MARK: - Evidence processing

    private func process(evidence: EnergyPolicy.Evidence) {
        currentActivity = motion.currentActivity
        let newMode = policy.process(evidence)
        if newMode != mode {
            mode = newMode
            applyModeChange()
        }
    }

    /// SLC fix or geofence exit while stationary: the user is moving again.
    private func noteMovementWakeup() {
        guard isRecording else { return }
        let evidence = EnergyPolicy.Evidence(
            activity: .unknown,
            confidence: .high,
            speedMps: 10, // certain displacement; well above any moving threshold
            timestamp: Date().timeIntervalSince1970
        )
        process(evidence: evidence)
    }

    private func applyModeChange() {
        persistMode()
        applyCurrentMode()
        if mode == .stationary {
            // GPS is about to go quiet for potentially hours; persist the
            // buffered tail of the track now.
            flushSoon()
        }
    }

    private func applyCurrentMode() {
        let effectiveMode = policy.mode
        if effectiveMode != mode {
            mode = effectiveMode
            persistMode()
        }
        guard isRecording else { return }
        location.apply(profile: EnergyPolicy.profile(for: mode))
    }

    private func persistMode() {
        UserDefaults.standard.set(mode.rawValue, forKey: SettingsKeys.lastTrackingMode)
    }

    // MARK: - Location handling

    private func handle(locations: [CLLocation]) {
        guard isRecording else { return }
        for fix in locations {
            handle(fix: fix)
        }
    }

    private func handle(fix: CLLocation) {
        // A fix arriving while stationary means SLC woke us: movement evidence.
        if mode == .stationary, let previous = lastLocation {
            let meters = fix.distance(from: previous)
            let seconds = fix.timestamp.timeIntervalSince(previous.timestamp)
            if meters > 100, seconds > 0 {
                process(evidence: EnergyPolicy.Evidence(
                    activity: .unknown,
                    confidence: .high,
                    speedMps: max(meters / seconds, 1),
                    timestamp: fix.timestamp.timeIntervalSince1970
                ))
            }
        }

        lastLocation = fix
        lastFixDate = Date()

        guard fix.horizontalAccuracy >= 0,
              fix.horizontalAccuracy <= maximumAcceptedHorizontalAccuracy else { return }

        // GPS speed is additional evidence for the energy policy.
        if fix.speed >= 0 {
            process(evidence: EnergyPolicy.Evidence(
                activity: .unknown,
                confidence: .high,
                speedMps: fix.speed,
                timestamp: fix.timestamp.timeIntervalSince1970
            ))
        }

        let point = TrackPoint(
            unixTime: Int32(clamping: Int(fix.timestamp.timeIntervalSince1970)),
            latitude: fix.coordinate.latitude,
            longitude: fix.coordinate.longitude,
            altitudeMeters: fix.verticalAccuracy >= 0 ? fix.altitude : 0,
            speedMps: fix.speed,
            courseDegrees: fix.course,
            horizontalAccuracyMeters: fix.horizontalAccuracy,
            activity: currentActivity
        )
        sessionPointCount += 1
        livePathCoordinates.append(fix.coordinate)
        if livePathCoordinates.count > 5_000 {
            livePathCoordinates.removeFirst(livePathCoordinates.count - 5_000)
        }
        Task { [store] in
            await store.append(point)
        }
    }

    // MARK: - Map helpers

    func requestSingleLocation() {
        location.requestSingleLocation()
    }
}
