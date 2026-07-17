import CoreLocation
import Foundation
import TrackerKit

/// Owns the `CLLocationManager` and translates `TrackerKit.ModeProfile`
/// decisions into radio state.
///
/// Isolation note: this type is `@MainActor` (the main actor *is* an actor)
/// rather than a custom actor on purpose. `CLLocationManager` delivers
/// delegate callbacks on the run loop of the thread that created it; custom
/// actors run on cooperative-pool threads without run loops, which silently
/// breaks delegate delivery. Creating and using the manager on the main run
/// loop is the only configuration Core Location fully supports, and the
/// callback rate (≤ a few per minute in this app) is negligible main-thread work.
@MainActor
final class LocationService: NSObject {
    /// Batches of fixes from continuous GPS, significant-change wakeups,
    /// or the initial one-shot request.
    var onLocations: (@MainActor ([CLLocation]) -> Void)?
    /// The stationary geofence was exited (second wake trigger besides SLC).
    var onStationaryFenceExit: (@MainActor () -> Void)?
    var onAuthorizationChange: (@MainActor (CLAuthorizationStatus) -> Void)?

    private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined

    private var isAuthorized: Bool {
        authorizationStatus == .authorizedAlways || authorizationStatus == .authorizedWhenInUse
    }

    private let manager = CLLocationManager()
    // Only one live CLMonitor instance may exist per name, so a single
    // instance and a single event-loop task are kept for the app's lifetime.
    private var monitor: CLMonitor?
    private var monitorEventTask: Task<Void, Never>?
    private var isRecording = false
    private var currentProfile: ModeProfile?

    private static let stationaryFenceIdentifier = "stationary-fence"
    private static let stationaryFenceRadiusMeters: CLLocationDistance = 150

    override init() {
        super.init()
        manager.delegate = self
        manager.pausesLocationUpdatesAutomatically = false
        manager.activityType = .other
        authorizationStatus = manager.authorizationStatus
    }

    // MARK: - Authorization

    /// Two-step permission flow: When-In-Use first…
    func requestWhenInUseAuthorization() {
        manager.requestWhenInUseAuthorization()
    }

    /// …then the Always upgrade (only meaningful once When-In-Use is granted).
    func requestAlwaysAuthorization() {
        manager.requestAlwaysAuthorization()
    }

    // MARK: - Recording lifecycle

    /// Starts recording with the given profile. Significant-change monitoring
    /// stays active for the whole recording so the system relaunches the app
    /// after termination or reboot.
    func startRecording(profile: ModeProfile) {
        isRecording = true
        // Requires the "location" background mode (declared in Info.plist).
        // Works with When-In-Use too, but only Always survives termination.
        manager.allowsBackgroundLocationUpdates = isAuthorized
        manager.showsBackgroundLocationIndicator = true
        manager.startMonitoringSignificantLocationChanges()
        apply(profile: profile)
    }

    func stopRecording() {
        isRecording = false
        currentProfile = nil
        manager.stopUpdatingLocation()
        manager.stopMonitoringSignificantLocationChanges()
        manager.allowsBackgroundLocationUpdates = false
        removeStationaryFence()
    }

    /// Reconfigures the GPS radio for a new tracking mode.
    func apply(profile: ModeProfile) {
        guard isRecording else { return }
        currentProfile = profile

        manager.desiredAccuracy = switch profile.accuracy {
        case .best: kCLLocationAccuracyBest
        case .hundredMeters: kCLLocationAccuracyHundredMeters
        }
        manager.distanceFilter = profile.distanceFilterMeters

        if profile.usesContinuousGPS {
            removeStationaryFence()
            manager.startUpdatingLocation()
        } else {
            // Stationary: GPS off. Wakeups come from SLC (still running) and
            // from a CLMonitor geofence around the resting position.
            manager.stopUpdatingLocation()
            if let center = manager.location?.coordinate {
                armStationaryFence(center: center)
            }
        }
    }

    /// One-shot fix, used to center the map before recording starts.
    func requestSingleLocation() {
        manager.requestLocation()
    }

    // MARK: - CLMonitor geofence

    private func sharedMonitor() async -> CLMonitor {
        if let monitor { return monitor }
        let created = await CLMonitor("GPSTrackerWakeups")
        monitor = created
        return created
    }

    private func armStationaryFence(center: CLLocationCoordinate2D) {
        Task { [weak self] in
            guard let self else { return }
            let monitor = await sharedMonitor()
            let condition = CLMonitor.CircularGeographicCondition(
                center: center,
                radius: Self.stationaryFenceRadiusMeters
            )
            await monitor.add(condition, identifier: Self.stationaryFenceIdentifier, assuming: .satisfied)
            startMonitorEventLoopIfNeeded(monitor)
        }
    }

    private func removeStationaryFence() {
        // CLMonitor conditions persist across process launches, so this must
        // run even when no fence was armed in this process.
        Task { [weak self] in
            guard let self else { return }
            await sharedMonitor().remove(Self.stationaryFenceIdentifier)
        }
    }

    private func startMonitorEventLoopIfNeeded(_ monitor: CLMonitor) {
        guard monitorEventTask == nil else { return }
        monitorEventTask = Task { [weak self] in
            do {
                for try await event in await monitor.events {
                    guard let self else { break }
                    if event.identifier == Self.stationaryFenceIdentifier, event.state == .unsatisfied {
                        self.onStationaryFenceExit?()
                    }
                }
            } catch {
                // Monitoring ended; SLC remains as the fallback wake source.
                self?.monitorEventTask = nil
            }
        }
    }
}

// MARK: - CLLocationManagerDelegate

extension LocationService: CLLocationManagerDelegate {
    // The manager is created on the main thread, so Core Location delivers
    // these callbacks on the main run loop; `assumeIsolated` makes that
    // guarantee explicit to the Swift 6 concurrency checker.

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        MainActor.assumeIsolated {
            onLocations?(locations)
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        MainActor.assumeIsolated {
            authorizationStatus = self.manager.authorizationStatus
            if isRecording {
                self.manager.allowsBackgroundLocationUpdates = isAuthorized
            }
            onAuthorizationChange?(authorizationStatus)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Transient failures (e.g. kCLErrorLocationUnknown) are expected;
        // Core Location keeps trying on its own.
    }
}
