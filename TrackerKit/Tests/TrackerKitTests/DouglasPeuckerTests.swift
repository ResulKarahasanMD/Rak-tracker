import Testing
@testable import TrackerKit

@Suite("Douglas-Peucker core (planar)")
struct DouglasPeuckerPlanarTests {
    @Test func degenerateInputsAreReturnedUnchanged() {
        #expect(DouglasPeucker.simplifyIndices(xs: [], ys: [], tolerance: 1) == [])
        #expect(DouglasPeucker.simplifyIndices(xs: [1], ys: [2], tolerance: 1) == [0])
        #expect(DouglasPeucker.simplifyIndices(xs: [1, 2], ys: [2, 3], tolerance: 1) == [0, 1])
    }

    @Test func collinearPointsCollapseToEndpointsEvenWithZeroTolerance() {
        let xs: [Double] = [0, 1, 2, 3, 4]
        let ys: [Double] = [0, 1, 2, 3, 4]
        #expect(DouglasPeucker.simplifyIndices(xs: xs, ys: ys, tolerance: 0) == [0, 4])
    }

    @Test func zeroToleranceKeepsEveryNonCollinearPoint() {
        let xs: [Double] = [0, 1, 2, 3, 4]
        let ys: [Double] = [0, 1, 0, 1, 0]
        #expect(DouglasPeucker.simplifyIndices(xs: xs, ys: ys, tolerance: 0) == [0, 1, 2, 3, 4])
    }

    @Test func largeToleranceKeepsOnlyEndpoints() {
        let xs: [Double] = [0, 1, 2, 3, 4]
        let ys: [Double] = [0, 1, 0, 1, 0]
        #expect(DouglasPeucker.simplifyIndices(xs: xs, ys: ys, tolerance: 10) == [0, 4])
    }

    @Test func toleranceIsAnExclusiveThreshold() {
        // Middle point deviates exactly 1.0 from the baseline; deviation must be
        // strictly greater than tolerance to be kept.
        let xs: [Double] = [0, 1, 2]
        let ys: [Double] = [0, 1, 0]
        #expect(DouglasPeucker.simplifyIndices(xs: xs, ys: ys, tolerance: 1.0) == [0, 2])
        #expect(DouglasPeucker.simplifyIndices(xs: xs, ys: ys, tolerance: 0.999) == [0, 1, 2])
    }

    @Test func closedLoopDoesNotCrash() {
        // First and last points identical: perpendicular distance degenerates to
        // point distance; must still terminate and keep the farthest point.
        let xs: [Double] = [0, 5, 0]
        let ys: [Double] = [0, 0, 0]
        #expect(DouglasPeucker.simplifyIndices(xs: xs, ys: ys, tolerance: 1) == [0, 1, 2])
    }

    @Test func longPolylineDoesNotOverflowStack() {
        // Iterative implementation must survive pathological (sorted) input that
        // would recurse O(n) deep in a naive recursive version.
        let n = 200_000
        var xs = [Double](); xs.reserveCapacity(n)
        var ys = [Double](); ys.reserveCapacity(n)
        for i in 0..<n {
            xs.append(Double(i))
            ys.append(Double(i) * 1e-4) // slightly curved so nothing collapses trivially
        }
        let kept = DouglasPeucker.simplifyIndices(xs: xs, ys: ys, tolerance: 0.5)
        #expect(kept.first == 0)
        #expect(kept.last == n - 1)
        #expect(kept.count < n)
    }
}

@Suite("Douglas-Peucker on track points (meters)")
struct DouglasPeuckerTrackTests {
    private func makePoint(_ index: Int, lat: Double, lon: Double) -> TrackPoint {
        TrackPoint(
            unixTime: Int32(1_700_000_000 + index * 10),
            latitude: lat, longitude: lon,
            altitudeMeters: 0, speedMps: 1, courseDegrees: 0,
            horizontalAccuracyMeters: 5, activity: .walking
        )
    }

    @Test func simplifiedTrackIsOrderedSubsetWithSameEndpoints() {
        // Wobbly walk heading north with ~±4 m of lateral GPS noise.
        var points: [TrackPoint] = []
        for i in 0..<100 {
            let lat = 52.5 + Double(i) * 0.0001            // ~11 m steps north
            let lon = 13.4 + (i % 2 == 0 ? 0.00004 : -0.00004) // ~±2.7 m wobble
            points.append(makePoint(i, lat: lat, lon: lon))
        }
        let simplified = DouglasPeucker.simplify(points, toleranceMeters: 10)

        #expect(simplified.count < points.count)
        #expect(simplified.first == points.first)
        #expect(simplified.last == points.last)
        // Must be a subsequence of the input.
        var cursor = 0
        for p in simplified {
            while cursor < points.count, points[cursor] != p { cursor += 1 }
            #expect(cursor < points.count, "output point not found in input order")
        }
    }

    @Test func sharpTurnIsPreserved() {
        // L-shaped track: north for ~111 m, then east for ~111 m.
        var points: [TrackPoint] = []
        for i in 0...10 { points.append(makePoint(i, lat: 52.5 + Double(i) * 0.0001, lon: 13.4)) }
        for i in 1...10 { points.append(makePoint(10 + i, lat: 52.501, lon: 13.4 + Double(i) * 0.0001)) }
        let simplified = DouglasPeucker.simplify(points, toleranceMeters: 15)
        // The corner point must survive aggressive simplification.
        #expect(simplified.contains(points[10]))
        #expect(simplified.count >= 3)
    }

    @Test func toleranceZeroLosesNothingMeaningful() {
        let points = (0..<5).map { makePoint($0, lat: 52.5 + Double($0 % 3) * 0.001, lon: 13.4 + Double($0) * 0.001) }
        let simplified = DouglasPeucker.simplify(points, toleranceMeters: 0)
        #expect(simplified.first == points.first)
        #expect(simplified.last == points.last)
    }
}

@Suite("Haversine")
struct HaversineTests {
    @Test func oneDegreeOfLatitude() {
        let d = Haversine.distanceMeters(lat1: 52.0, lon1: 13.0, lat2: 53.0, lon2: 13.0)
        #expect(abs(d - 111_195) < 200)
    }

    @Test func berlinToParis() {
        let d = Haversine.distanceMeters(lat1: 52.5200, lon1: 13.4050, lat2: 48.8566, lon2: 2.3522)
        #expect(abs(d - 878_000) < 8_000)
    }

    @Test func zeroDistance() {
        #expect(Haversine.distanceMeters(lat1: 10, lon1: 20, lat2: 10, lon2: 20) == 0)
    }
}
