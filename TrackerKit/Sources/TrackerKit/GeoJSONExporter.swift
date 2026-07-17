/// GeoJSON (RFC 7946) export: one FeatureCollection containing a single
/// LineString feature. Coordinates are `[longitude, latitude, altitude]`.
public enum GeoJSONExporter {
    public static func export(points: [TrackPoint], name: String) -> String {
        var output = ""
        write(points: points, name: name, to: &output)
        return output
    }

    public static func write<Target: TextOutputStream>(
        points: [TrackPoint],
        name: String,
        to target: inout Target
    ) {
        target.write(#"{"type":"FeatureCollection","features":["#)
        target.write(#"{"type":"Feature","properties":{"name":"\#(escapeJSON(name))""#)
        if let first = points.first, let last = points.last {
            target.write(#","start":"\#(UnixTime.iso8601String(first.timestamp))""#)
            target.write(#","end":"\#(UnixTime.iso8601String(last.timestamp))""#)
        }
        target.write(#"},"geometry":{"type":"LineString","coordinates":["#)
        var isFirst = true
        for point in points {
            if !isFirst { target.write(",") }
            isFirst = false
            target.write(
                "[\(FixedPoint.coordinateString(point.lonE7)),"
                + "\(FixedPoint.coordinateString(point.latE7)),"
                + "\(point.altitude)]"
            )
        }
        target.write("]}}]}")
    }

    static func escapeJSON(_ text: String) -> String {
        var escaped = ""
        escaped.reserveCapacity(text.count)
        for scalar in text.unicodeScalars {
            switch scalar {
            case "\"": escaped += "\\\""
            case "\\": escaped += "\\\\"
            case "\n": escaped += "\\n"
            case "\r": escaped += "\\r"
            case "\t": escaped += "\\t"
            case let s where s.value < 0x20:
                let digits = String(s.value, radix: 16)
                escaped += "\\u" + String(repeating: "0", count: 4 - digits.count) + digits
            default:
                escaped.unicodeScalars.append(scalar)
            }
        }
        return escaped
    }
}
