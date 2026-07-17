/// The three GPS duty-cycle modes of the tracker.
public enum TrackingMode: String, Sendable, Hashable, CaseIterable {
    /// GPS radio off; wakeups come from significant-change / region monitoring.
    case stationary
    /// Continuous updates at reduced accuracy (the adaptive default while moving).
    case moving
    /// User-enabled best accuracy with a tight distance filter.
    case precise
}

/// Location-manager configuration associated with a `TrackingMode`.
public struct ModeProfile: Sendable, Hashable {
    public enum Accuracy: Sendable, Hashable {
        case best
        case hundredMeters
    }

    /// `false` means `stopUpdatingLocation()` + significant-change/region wakeups only.
    public let usesContinuousGPS: Bool
    public let accuracy: Accuracy
    public let distanceFilterMeters: Double

    public init(usesContinuousGPS: Bool, accuracy: Accuracy, distanceFilterMeters: Double) {
        self.usesContinuousGPS = usesContinuousGPS
        self.accuracy = accuracy
        self.distanceFilterMeters = distanceFilterMeters
    }
}

/// Pure, fully-testable state machine that decides the tracking mode from
/// motion-activity and speed evidence. All timing is injected through the
/// evidence timestamps, so no clocks are involved.
public struct EnergyPolicy: Sendable {
    public struct Config: Sendable {
        /// Continuous stationary evidence required before turning GPS off.
        public var stationaryDebounceSeconds: Double
        /// GPS speed at or above this counts as movement regardless of activity.
        public var movingSpeedThresholdMps: Double

        public init(stationaryDebounceSeconds: Double = 180, movingSpeedThresholdMps: Double = 0.5) {
            self.stationaryDebounceSeconds = stationaryDebounceSeconds
            self.movingSpeedThresholdMps = movingSpeedThresholdMps
        }
    }

    public enum Confidence: Sendable, Hashable {
        case low, medium, high
    }

    /// One observation fed into the state machine (from CMMotionActivity
    /// and/or the latest GPS fix).
    public struct Evidence: Sendable {
        public var activity: ActivityFlag
        public var confidence: Confidence
        public var speedMps: Double?
        /// Monotonic or unix seconds; only differences matter.
        public var timestamp: Double

        public init(activity: ActivityFlag, confidence: Confidence, speedMps: Double?, timestamp: Double) {
            self.activity = activity
            self.confidence = confidence
            self.speedMps = speedMps
            self.timestamp = timestamp
        }
    }

    /// User-enabled precise mode; overrides the adaptive decision.
    public var preciseEnabled = false

    private let config: Config
    /// Start in `.moving` so a fresh recording acquires a first fix quickly.
    private var adaptiveMode: TrackingMode = .moving
    private var stationaryEvidenceSince: Double?

    public init(config: Config = Config()) {
        self.config = config
    }

    public var mode: TrackingMode {
        preciseEnabled ? .precise : adaptiveMode
    }

    /// Feeds one piece of evidence and returns the resulting mode.
    @discardableResult
    public mutating func process(_ evidence: Evidence) -> TrackingMode {
        let speedSaysMoving: Bool
        if let speed = evidence.speedMps, !speed.isNaN {
            speedSaysMoving = speed >= config.movingSpeedThresholdMps
        } else {
            speedSaysMoving = false
        }
        let isConfident = evidence.confidence != .low
        let activitySaysMoving = isConfident
            && evidence.activity != .stationary
            && evidence.activity != .unknown

        if speedSaysMoving || activitySaysMoving {
            stationaryEvidenceSince = nil
            adaptiveMode = .moving
        } else if isConfident, evidence.activity == .stationary {
            if let since = stationaryEvidenceSince {
                if evidence.timestamp - since >= config.stationaryDebounceSeconds {
                    adaptiveMode = .stationary
                }
            } else {
                stationaryEvidenceSince = evidence.timestamp
            }
        }
        // Low-confidence or unknown evidence without speed: no state change.
        return mode
    }

    /// The location-manager profile for each mode. These values are the
    /// core of the battery design: never run best-accuracy GPS unless the
    /// user explicitly asked for it, and turn GPS fully off when stationary.
    public static func profile(for mode: TrackingMode) -> ModeProfile {
        switch mode {
        case .stationary:
            ModeProfile(usesContinuousGPS: false, accuracy: .hundredMeters, distanceFilterMeters: 100)
        case .moving:
            ModeProfile(usesContinuousGPS: true, accuracy: .hundredMeters, distanceFilterMeters: 75)
        case .precise:
            ModeProfile(usesContinuousGPS: true, accuracy: .best, distanceFilterMeters: 10)
        }
    }
}

/// Rough battery-drain heuristics shown in the UI. Values are conservative
/// estimates for a recent iPhone (percent of full charge per hour).
public enum BatteryEstimator {
    public static func percentPerHour(for mode: TrackingMode) -> Double {
        switch mode {
        case .stationary: 0.1
        case .moving: 0.9
        case .precise: 3.0
        }
    }

    /// Estimated drain over a day given hours spent in each mode.
    public static func estimateDailyPercent(hoursByMode: [TrackingMode: Double]) -> Double {
        hoursByMode.reduce(0) { total, entry in
            total + percentPerHour(for: entry.key) * entry.value
        }
    }
}
