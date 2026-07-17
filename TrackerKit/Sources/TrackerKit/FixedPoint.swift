/// Fixed-point codecs used by the on-disk point format.
///
/// Coordinates are stored as `Int32` in 1e-7 degree units (~1.1 cm of
/// resolution at the equator), scalar fields as `Int16`. Invalid scalar
/// values (Core Location reports them as negative) are stored as `-1`.
public enum FixedPoint {
    /// One coordinate least-significant bit in degrees.
    public static let coordinateScale = 10_000_000.0

    // MARK: Coordinates (1e-7 degrees, Int32)

    public static func encodeCoordinate(_ degrees: Double) -> Int32 {
        guard !degrees.isNaN else { return 0 }
        let clamped = min(max(degrees, -180.0), 180.0)
        return Int32((clamped * coordinateScale).rounded())
    }

    public static func decodeCoordinate(_ value: Int32) -> Double {
        Double(value) / coordinateScale
    }

    /// Locale-independent decimal rendering with exactly 7 fraction digits,
    /// suitable for GPX/GeoJSON/CSV output.
    public static func coordinateString(_ value: Int32) -> String {
        let magnitude = Int64(value).magnitude
        let integerPart = magnitude / 10_000_000
        let fraction = magnitude % 10_000_000
        var fractionDigits = String(fraction)
        if fractionDigits.count < 7 {
            fractionDigits = String(repeating: "0", count: 7 - fractionDigits.count) + fractionDigits
        }
        let sign = value < 0 ? "-" : ""
        return "\(sign)\(integerPart).\(fractionDigits)"
    }

    // MARK: Altitude (meters, Int16)

    public static func encodeAltitude(_ meters: Double) -> Int16 {
        guard !meters.isNaN else { return 0 }
        return clampToInt16(meters.rounded())
    }

    public static func decodeAltitude(_ value: Int16) -> Double {
        Double(value)
    }

    // MARK: Speed (decimeters per second, Int16; -1 = invalid)

    public static func encodeSpeed(_ metersPerSecond: Double) -> Int16 {
        guard !metersPerSecond.isNaN, metersPerSecond >= 0 else { return -1 }
        return clampToInt16((metersPerSecond * 10).rounded())
    }

    public static func decodeSpeed(_ value: Int16) -> Double? {
        value >= 0 ? Double(value) / 10 : nil
    }

    // MARK: Course (degrees, Int16; -1 = invalid)

    public static func encodeCourse(_ degrees: Double) -> Int16 {
        guard !degrees.isNaN, degrees >= 0 else { return -1 }
        return clampToInt16(degrees.rounded())
    }

    public static func decodeCourse(_ value: Int16) -> Double? {
        value >= 0 ? Double(value) : nil
    }

    // MARK: Horizontal accuracy (meters, Int16; -1 = invalid)

    public static func encodeHAccuracy(_ meters: Double) -> Int16 {
        guard !meters.isNaN, meters >= 0 else { return -1 }
        return clampToInt16(meters.rounded())
    }

    public static func decodeHAccuracy(_ value: Int16) -> Double? {
        value >= 0 ? Double(value) : nil
    }

    private static func clampToInt16(_ value: Double) -> Int16 {
        Int16(min(max(value, Double(Int16.min)), Double(Int16.max)))
    }
}
