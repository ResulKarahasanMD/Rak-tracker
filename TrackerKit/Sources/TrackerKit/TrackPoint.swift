/// Motion activity classification stored with every point.
/// Raw values are persisted in SQLite and must never change.
public enum ActivityFlag: UInt8, Sendable, Hashable, CaseIterable {
    case unknown = 0
    case stationary = 1
    case walking = 2
    case running = 3
    case cycling = 4
    case automotive = 5

    public var label: String {
        switch self {
        case .unknown: "unknown"
        case .stationary: "stationary"
        case .walking: "walking"
        case .running: "running"
        case .cycling: "cycling"
        case .automotive: "automotive"
        }
    }
}

/// One recorded location sample in its compact storage representation:
/// 4 (ts) + 4 (lat) + 4 (lon) + 2 (alt) + 2 (speed) + 2 (course) + 2 (hAcc) + 1 (activity)
/// = 21 bytes of payload per point.
public struct TrackPoint: Hashable, Sendable {
    /// Unix timestamp, seconds.
    public var timestamp: Int32
    /// Latitude in 1e-7 degrees.
    public var latE7: Int32
    /// Longitude in 1e-7 degrees.
    public var lonE7: Int32
    /// Altitude in meters.
    public var altitude: Int16
    /// Speed in decimeters per second; -1 when invalid.
    public var speed: Int16
    /// Course in degrees clockwise from true north; -1 when invalid.
    public var course: Int16
    /// Horizontal accuracy in meters; -1 when invalid.
    public var hAccuracy: Int16
    public var activity: ActivityFlag

    /// Sum of the encoded field widths, in bytes.
    public static let encodedFieldByteCount = 21

    public init(
        timestamp: Int32, latE7: Int32, lonE7: Int32,
        altitude: Int16, speed: Int16, course: Int16, hAccuracy: Int16,
        activity: ActivityFlag
    ) {
        self.timestamp = timestamp
        self.latE7 = latE7
        self.lonE7 = lonE7
        self.altitude = altitude
        self.speed = speed
        self.course = course
        self.hAccuracy = hAccuracy
        self.activity = activity
    }

    /// Convenience initializer taking natural (SI / degree) units.
    public init(
        unixTime: Int32,
        latitude: Double, longitude: Double,
        altitudeMeters: Double, speedMps: Double, courseDegrees: Double,
        horizontalAccuracyMeters: Double, activity: ActivityFlag
    ) {
        self.init(
            timestamp: unixTime,
            latE7: FixedPoint.encodeCoordinate(latitude),
            lonE7: FixedPoint.encodeCoordinate(longitude),
            altitude: FixedPoint.encodeAltitude(altitudeMeters),
            speed: FixedPoint.encodeSpeed(speedMps),
            course: FixedPoint.encodeCourse(courseDegrees),
            hAccuracy: FixedPoint.encodeHAccuracy(horizontalAccuracyMeters),
            activity: activity
        )
    }

    public var latitude: Double { FixedPoint.decodeCoordinate(latE7) }
    public var longitude: Double { FixedPoint.decodeCoordinate(lonE7) }
    public var altitudeMeters: Double { FixedPoint.decodeAltitude(altitude) }
    public var speedMps: Double? { FixedPoint.decodeSpeed(speed) }
    public var courseDegrees: Double? { FixedPoint.decodeCourse(course) }
    public var horizontalAccuracyMeters: Double? { FixedPoint.decodeHAccuracy(hAccuracy) }
}
