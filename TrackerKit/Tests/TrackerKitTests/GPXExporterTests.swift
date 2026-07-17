import Testing
@testable import TrackerKit

@Suite("ISO 8601 timestamp formatting")
struct UnixTimeTests {
    @Test func epoch() {
        #expect(UnixTime.iso8601String(0) == "1970-01-01T00:00:00Z")
    }

    @Test func knownInstant() {
        #expect(UnixTime.iso8601String(1_705_314_600) == "2024-01-15T10:30:00Z")
    }

    @Test func leapDay() {
        #expect(UnixTime.iso8601String(1_709_208_000) == "2024-02-29T12:00:00Z")
    }

    @Test func zeroPadding() {
        // 2001-02-03T04:05:06Z
        #expect(UnixTime.iso8601String(981_173_106) == "2001-02-03T04:05:06Z")
    }
}

@Suite("Fixed-point coordinate string rendering")
struct CoordinateStringTests {
    @Test func rendersSevenDecimalsLocaleIndependently() {
        #expect(FixedPoint.coordinateString(525_200_066) == "52.5200066")
        #expect(FixedPoint.coordinateString(134_049_540) == "13.4049540")
        #expect(FixedPoint.coordinateString(0) == "0.0000000")
        #expect(FixedPoint.coordinateString(-5) == "-0.0000005")
        #expect(FixedPoint.coordinateString(1_800_000_000) == "180.0000000")
        #expect(FixedPoint.coordinateString(-900_000_000) == "-90.0000000")
    }
}

@Suite("GPX 1.1 export")
struct GPXExporterTests {
    private let berlin = TrackPoint(
        unixTime: 1_705_314_600,
        latitude: 52.5200066, longitude: 13.4049540,
        altitudeMeters: 34, speedMps: 1.25, courseDegrees: 275,
        horizontalAccuracyMeters: 5, activity: .walking
    )
    private let berlin2 = TrackPoint(
        unixTime: 1_705_314_660,
        latitude: 52.5210000, longitude: 13.4060000,
        altitudeMeters: 35, speedMps: 1.30, courseDegrees: 280,
        horizontalAccuracyMeters: 4, activity: .walking
    )

    @Test func goldenOutput() {
        let gpx = GPXExporter.export(points: [berlin, berlin2], trackName: "Morning walk")
        let expected = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="GPS Tracker" xmlns="http://www.topografix.com/GPX/1/1" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:schemaLocation="http://www.topografix.com/GPX/1/1 http://www.topografix.com/GPX/1/1/gpx.xsd">
        <metadata>
        <name>Morning walk</name>
        <time>2024-01-15T10:30:00Z</time>
        </metadata>
        <trk>
        <name>Morning walk</name>
        <trkseg>
        <trkpt lat="52.5200066" lon="13.4049540">
        <ele>34</ele>
        <time>2024-01-15T10:30:00Z</time>
        </trkpt>
        <trkpt lat="52.5210000" lon="13.4060000">
        <ele>35</ele>
        <time>2024-01-15T10:31:00Z</time>
        </trkpt>
        </trkseg>
        </trk>
        </gpx>

        """
        #expect(gpx == expected)
    }

    @Test func escapesXMLSpecialCharactersInTrackName() {
        let gpx = GPXExporter.export(points: [berlin], trackName: "A <b> & \"c\" 'd'")
        #expect(gpx.contains("<name>A &lt;b&gt; &amp; &quot;c&quot; &apos;d&apos;</name>"))
        #expect(!gpx.contains("<name>A <b>"))
    }

    @Test func splitsSegmentsOnTimeGaps() {
        // 20 minutes between points: must produce two <trkseg> elements.
        let later = TrackPoint(
            unixTime: berlin.timestamp + 1200,
            latitude: 52.53, longitude: 13.41,
            altitudeMeters: 36, speedMps: 1, courseDegrees: 0,
            horizontalAccuracyMeters: 5, activity: .walking
        )
        let gpx = GPXExporter.export(points: [berlin, berlin2, later], trackName: "Split", segmentGapSeconds: 300)
        #expect(occurrences(of: "<trkseg>", in: gpx) == 2)
        #expect(occurrences(of: "</trkseg>", in: gpx) == 2)
    }

    private func occurrences(of needle: String, in haystack: String) -> Int {
        var count = 0
        var remainder = Substring(haystack)
        while let found = remainder.firstRange(of: needle) {
            count += 1
            remainder = remainder[found.upperBound...]
        }
        return count
    }

    @Test func emptyExportIsStillValidGPX() {
        let gpx = GPXExporter.export(points: [], trackName: "Empty")
        #expect(gpx.hasPrefix("<?xml version=\"1.0\" encoding=\"UTF-8\"?>"))
        #expect(gpx.contains("<gpx version=\"1.1\""))
        #expect(gpx.contains("</gpx>"))
        #expect(!gpx.contains("<trkpt"))
    }

    @Test func streamingAndStringOutputsMatch() {
        var streamed = ""
        GPXExporter.write(points: [berlin, berlin2], trackName: "Morning walk", to: &streamed)
        #expect(streamed == GPXExporter.export(points: [berlin, berlin2], trackName: "Morning walk"))
    }
}

@Suite("GeoJSON export")
struct GeoJSONExporterTests {
    private let p1 = TrackPoint(
        unixTime: 1_705_314_600, latitude: 52.5200066, longitude: 13.4049540,
        altitudeMeters: 34, speedMps: 1, courseDegrees: 0,
        horizontalAccuracyMeters: 5, activity: .walking
    )
    private let p2 = TrackPoint(
        unixTime: 1_705_314_660, latitude: 52.5210000, longitude: 13.4060000,
        altitudeMeters: 35, speedMps: 1, courseDegrees: 0,
        horizontalAccuracyMeters: 5, activity: .walking
    )

    @Test func goldenOutput() {
        let json = GeoJSONExporter.export(points: [p1, p2], name: "Morning walk")
        let expected = #"{"type":"FeatureCollection","features":[{"type":"Feature","properties":{"name":"Morning walk","start":"2024-01-15T10:30:00Z","end":"2024-01-15T10:31:00Z"},"geometry":{"type":"LineString","coordinates":[[13.4049540,52.5200066,34],[13.4060000,52.5210000,35]]}}]}"#
        #expect(json == expected)
    }

    @Test func escapesJSONStringCharacters() {
        let json = GeoJSONExporter.export(points: [p1], name: "quote \" backslash \\ newline \n")
        #expect(json.contains(#""name":"quote \" backslash \\ newline \n""#))
    }

    @Test func longitudeComesFirst() {
        let json = GeoJSONExporter.export(points: [p1], name: "order")
        #expect(json.contains("[13.4049540,52.5200066,34]"))
    }
}

@Suite("CSV export")
struct CSVExporterTests {
    private let p1 = TrackPoint(
        unixTime: 1_705_314_600, latitude: 52.5200066, longitude: 13.4049540,
        altitudeMeters: 34, speedMps: 1.25, courseDegrees: 275,
        horizontalAccuracyMeters: 5, activity: .walking
    )

    @Test func goldenOutput() {
        let csv = CSVExporter.export(points: [p1])
        let expected = """
        timestamp,iso_time,latitude,longitude,altitude_m,speed_mps,course_deg,h_accuracy_m,activity
        1705314600,2024-01-15T10:30:00Z,52.5200066,13.4049540,34,1.3,275,5,walking

        """
        #expect(csv == expected)
    }

    @Test func invalidFieldsAreEmpty() {
        let p = TrackPoint(
            unixTime: 1_705_314_600, latitude: 1, longitude: 2,
            altitudeMeters: 0, speedMps: -1, courseDegrees: -1,
            horizontalAccuracyMeters: -1, activity: .unknown
        )
        let csv = CSVExporter.export(points: [p])
        let dataLine = csv.split(separator: "\n")[1]
        #expect(dataLine.hasSuffix(",0,,,,unknown"))
    }
}
