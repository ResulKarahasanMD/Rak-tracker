import Testing
@testable import TrackerKit

@Suite("Fixed-point coordinate codec")
struct FixedPointCoordinateTests {
    @Test func encodeKnownCoordinate() {
        #expect(FixedPoint.encodeCoordinate(52.5200066) == 525_200_066)
        #expect(FixedPoint.encodeCoordinate(13.4049540) == 134_049_540)
        #expect(FixedPoint.encodeCoordinate(-77.4166667) == -774_166_667)
        #expect(FixedPoint.encodeCoordinate(0) == 0)
    }

    @Test func decodeKnownCoordinate() {
        #expect(FixedPoint.decodeCoordinate(525_200_066) == 52.5200066)
        #expect(FixedPoint.decodeCoordinate(-774_166_667) == -77.4166667)
        #expect(FixedPoint.decodeCoordinate(0) == 0)
    }

    @Test func roundTripStaysWithinHalfLSB() {
        let samples: [Double] = [52.5200066, -33.8688197, 179.9999999, -179.9999999,
                                 89.9999999, -89.9999999, 0.0000001, -0.0000001, 41.0]
        for degrees in samples {
            let decoded = FixedPoint.decodeCoordinate(FixedPoint.encodeCoordinate(degrees))
            #expect(abs(decoded - degrees) <= 0.5e-7, "round-trip failed for \(degrees)")
        }
    }

    @Test func poles() {
        #expect(FixedPoint.encodeCoordinate(90) == 900_000_000)
        #expect(FixedPoint.encodeCoordinate(-90) == -900_000_000)
    }

    @Test func antimeridian() {
        #expect(FixedPoint.encodeCoordinate(180) == 1_800_000_000)
        #expect(FixedPoint.encodeCoordinate(-180) == -1_800_000_000)
    }

    @Test func clampsOutOfRangeInsteadOfOverflowing() {
        #expect(FixedPoint.encodeCoordinate(1000) == 1_800_000_000)
        #expect(FixedPoint.encodeCoordinate(-1000) == -1_800_000_000)
        #expect(FixedPoint.encodeCoordinate(.infinity) == 1_800_000_000)
        #expect(FixedPoint.encodeCoordinate(-.infinity) == -1_800_000_000)
        #expect(FixedPoint.encodeCoordinate(.nan) == 0)
    }

    @Test func rounding() {
        #expect(FixedPoint.encodeCoordinate(0.0000002) == 2)
        #expect(FixedPoint.encodeCoordinate(0.00000005) == 1) // half rounds away from zero
    }
}

@Suite("Fixed-point scalar codecs")
struct FixedPointScalarTests {
    @Test func altitude() {
        #expect(FixedPoint.encodeAltitude(34.0) == 34)
        #expect(FixedPoint.encodeAltitude(12.6) == 13)
        #expect(FixedPoint.encodeAltitude(-421.4) == -421)
        #expect(FixedPoint.encodeAltitude(40_000) == 32_767)   // clamp high
        #expect(FixedPoint.encodeAltitude(-40_000) == -32_768) // clamp low
        #expect(FixedPoint.encodeAltitude(.nan) == 0)
        #expect(FixedPoint.decodeAltitude(34) == 34.0)
    }

    @Test func speedIsStoredAsDecimetersPerSecond() {
        #expect(FixedPoint.encodeSpeed(1.25) == 13) // 12.5 dm/s rounds away from zero
        #expect(FixedPoint.encodeSpeed(1.24) == 12)
        #expect(FixedPoint.encodeSpeed(0) == 0)
        #expect(FixedPoint.encodeSpeed(-1) == -1)      // invalid marker preserved
        #expect(FixedPoint.encodeSpeed(-27.5) == -1)   // any negative speed is invalid
        #expect(FixedPoint.encodeSpeed(5000) == 32_767)
        #expect(FixedPoint.decodeSpeed(13) == 1.3)
        #expect(FixedPoint.decodeSpeed(-1) == nil)
    }

    @Test func course() {
        #expect(FixedPoint.encodeCourse(0) == 0)
        #expect(FixedPoint.encodeCourse(275.4) == 275)
        #expect(FixedPoint.encodeCourse(359.6) == 360)
        #expect(FixedPoint.encodeCourse(-1) == -1)     // invalid marker
        #expect(FixedPoint.decodeCourse(275) == 275.0)
        #expect(FixedPoint.decodeCourse(-1) == nil)
    }

    @Test func horizontalAccuracy() {
        #expect(FixedPoint.encodeHAccuracy(5.4) == 5)
        #expect(FixedPoint.encodeHAccuracy(-1) == -1)  // invalid marker
        #expect(FixedPoint.encodeHAccuracy(1_000_000) == 32_767)
        #expect(FixedPoint.decodeHAccuracy(5) == 5.0)
        #expect(FixedPoint.decodeHAccuracy(-1) == nil)
    }
}

@Suite("TrackPoint")
struct TrackPointTests {
    @Test func convenienceInitEncodesAllFields() {
        let point = TrackPoint(
            unixTime: 1_705_314_600,
            latitude: 52.5200066,
            longitude: 13.4049540,
            altitudeMeters: 34.2,
            speedMps: 1.25,
            courseDegrees: 275.4,
            horizontalAccuracyMeters: 5.4,
            activity: .walking
        )
        #expect(point.timestamp == 1_705_314_600)
        #expect(point.latE7 == 525_200_066)
        #expect(point.lonE7 == 134_049_540)
        #expect(point.altitude == 34)
        #expect(point.speed == 13)
        #expect(point.course == 275)
        #expect(point.hAccuracy == 5)
        #expect(point.activity == .walking)
        #expect(abs(point.latitude - 52.5200066) <= 0.5e-7)
        #expect(abs(point.longitude - 13.4049540) <= 0.5e-7)
    }

    @Test func activityFlagRawValuesAreStable() {
        // Raw values are persisted in SQLite; they must never change.
        #expect(ActivityFlag.unknown.rawValue == 0)
        #expect(ActivityFlag.stationary.rawValue == 1)
        #expect(ActivityFlag.walking.rawValue == 2)
        #expect(ActivityFlag.running.rawValue == 3)
        #expect(ActivityFlag.cycling.rawValue == 4)
        #expect(ActivityFlag.automotive.rawValue == 5)
    }

    @Test func storedRecordIsCompact() {
        // 4 (ts) + 4 (lat) + 4 (lon) + 2+2+2+2 (alt/speed/course/hacc) + 1 (activity) = 21 bytes
        #expect(TrackPoint.encodedFieldByteCount == 21)
    }
}
