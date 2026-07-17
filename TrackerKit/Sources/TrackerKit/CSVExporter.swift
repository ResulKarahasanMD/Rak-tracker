/// CSV export with a fixed header. Invalid fields (speed/course/accuracy
/// reported as negative by Core Location) are left empty.
public enum CSVExporter {
    public static let header =
        "timestamp,iso_time,latitude,longitude,altitude_m,speed_mps,course_deg,h_accuracy_m,activity"

    public static func export(points: [TrackPoint]) -> String {
        var output = ""
        write(points: points, to: &output)
        return output
    }

    public static func write<Target: TextOutputStream>(points: [TrackPoint], to target: inout Target) {
        target.write(header)
        target.write("\n")
        for point in points {
            target.write(String(point.timestamp))
            target.write(",")
            target.write(UnixTime.iso8601String(point.timestamp))
            target.write(",")
            target.write(FixedPoint.coordinateString(point.latE7))
            target.write(",")
            target.write(FixedPoint.coordinateString(point.lonE7))
            target.write(",")
            target.write(String(point.altitude))
            target.write(",")
            target.write(speedString(point.speed))
            target.write(",")
            target.write(point.course >= 0 ? String(point.course) : "")
            target.write(",")
            target.write(point.hAccuracy >= 0 ? String(point.hAccuracy) : "")
            target.write(",")
            target.write(point.activity.label)
            target.write("\n")
        }
    }

    /// Renders decimeters-per-second as meters-per-second with one decimal,
    /// without any floating-point formatting involved.
    private static func speedString(_ decimetersPerSecond: Int16) -> String {
        guard decimetersPerSecond >= 0 else { return "" }
        return "\(decimetersPerSecond / 10).\(decimetersPerSecond % 10)"
    }
}
