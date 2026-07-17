/// GPX 1.1 export (https://www.topografix.com/GPX/1/1/gpx.xsd).
/// Output is written incrementally to any `TextOutputStream`, so large
/// exports never need the whole document in memory.
public enum GPXExporter {
    /// Consecutive points further apart in time than this start a new `<trkseg>`.
    public static let defaultSegmentGapSeconds: Int32 = 300

    public static func export(
        points: [TrackPoint],
        trackName: String,
        segmentGapSeconds: Int32 = GPXExporter.defaultSegmentGapSeconds
    ) -> String {
        var output = ""
        write(points: points, trackName: trackName, segmentGapSeconds: segmentGapSeconds, to: &output)
        return output
    }

    public static func write<Target: TextOutputStream>(
        points: [TrackPoint],
        trackName: String,
        segmentGapSeconds: Int32 = GPXExporter.defaultSegmentGapSeconds,
        to target: inout Target
    ) {
        let name = escapeXML(trackName)
        target.write("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n")
        target.write(
            "<gpx version=\"1.1\" creator=\"GPS Tracker\""
            + " xmlns=\"http://www.topografix.com/GPX/1/1\""
            + " xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\""
            + " xsi:schemaLocation=\"http://www.topografix.com/GPX/1/1 http://www.topografix.com/GPX/1/1/gpx.xsd\">\n"
        )
        target.write("<metadata>\n<name>\(name)</name>\n")
        if let first = points.first {
            target.write("<time>\(UnixTime.iso8601String(first.timestamp))</time>\n")
        }
        target.write("</metadata>\n")

        if !points.isEmpty {
            target.write("<trk>\n<name>\(name)</name>\n")
            var previousTimestamp: Int32?
            for point in points {
                if let previous = previousTimestamp, point.timestamp - previous > segmentGapSeconds {
                    target.write("</trkseg>\n<trkseg>\n")
                } else if previousTimestamp == nil {
                    target.write("<trkseg>\n")
                }
                target.write(
                    "<trkpt lat=\"\(FixedPoint.coordinateString(point.latE7))\""
                    + " lon=\"\(FixedPoint.coordinateString(point.lonE7))\">\n"
                )
                target.write("<ele>\(point.altitude)</ele>\n")
                target.write("<time>\(UnixTime.iso8601String(point.timestamp))</time>\n")
                target.write("</trkpt>\n")
                previousTimestamp = point.timestamp
            }
            target.write("</trkseg>\n</trk>\n")
        }
        target.write("</gpx>\n")
    }

    static func escapeXML(_ text: String) -> String {
        var escaped = ""
        escaped.reserveCapacity(text.count)
        for character in text {
            switch character {
            case "&": escaped += "&amp;"
            case "<": escaped += "&lt;"
            case ">": escaped += "&gt;"
            case "\"": escaped += "&quot;"
            case "'": escaped += "&apos;"
            default: escaped.append(character)
            }
        }
        return escaped
    }
}
