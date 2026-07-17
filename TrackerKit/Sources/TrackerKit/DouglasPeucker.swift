#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

/// Great-circle distance (spherical earth, R = 6371 km).
public enum Haversine {
    public static let earthRadiusMeters = 6_371_000.0

    public static func distanceMeters(lat1: Double, lon1: Double, lat2: Double, lon2: Double) -> Double {
        let phi1 = lat1 * .pi / 180
        let phi2 = lat2 * .pi / 180
        let dPhi = (lat2 - lat1) * .pi / 180
        let dLambda = (lon2 - lon1) * .pi / 180
        let a = sin(dPhi / 2) * sin(dPhi / 2)
            + cos(phi1) * cos(phi2) * sin(dLambda / 2) * sin(dLambda / 2)
        return 2 * earthRadiusMeters * atan2(a.squareRoot(), (1 - a).squareRoot())
    }
}

/// Iterative (explicit-stack) Douglas-Peucker polyline simplification.
/// Never recurses, so pathological inputs cannot overflow the call stack.
public enum DouglasPeucker {
    /// Core planar algorithm. Returns the sorted indices of points to keep.
    /// A point is kept when its perpendicular distance to the current
    /// baseline is strictly greater than `tolerance`.
    public static func simplifyIndices(xs: [Double], ys: [Double], tolerance: Double) -> [Int] {
        precondition(xs.count == ys.count, "coordinate arrays must have the same length")
        let count = xs.count
        guard count > 2 else { return Array(0..<count) }

        var keep = [Bool](repeating: false, count: count)
        keep[0] = true
        keep[count - 1] = true

        var stack: [(first: Int, last: Int)] = [(0, count - 1)]
        while let (first, last) = stack.popLast() {
            guard last - first > 1 else { continue }

            let x1 = xs[first], y1 = ys[first]
            let x2 = xs[last], y2 = ys[last]
            let dx = x2 - x1, dy = y2 - y1
            let baselineLengthSquared = dx * dx + dy * dy

            var maxDistance = -1.0
            var maxIndex = first
            for i in (first + 1)..<last {
                let distance: Double
                if baselineLengthSquared == 0 {
                    // Degenerate baseline (closed loop): fall back to point distance.
                    let px = xs[i] - x1, py = ys[i] - y1
                    distance = (px * px + py * py).squareRoot()
                } else {
                    distance = abs(dy * xs[i] - dx * ys[i] + x2 * y1 - y2 * x1)
                        / baselineLengthSquared.squareRoot()
                }
                if distance > maxDistance {
                    maxDistance = distance
                    maxIndex = i
                }
            }

            if maxDistance > tolerance {
                keep[maxIndex] = true
                stack.append((first, maxIndex))
                stack.append((maxIndex, last))
            }
        }
        return (0..<count).filter { keep[$0] }
    }

    /// Simplifies a GPS track with a tolerance expressed in meters.
    /// Points are projected onto a local equirectangular plane, which is
    /// accurate to well under 1% for track-sized extents.
    public static func simplify(_ points: [TrackPoint], toleranceMeters: Double) -> [TrackPoint] {
        guard points.count > 2 else { return points }

        let metersPerDegree = 111_319.49
        let midLatitudeRadians = points[points.count / 2].latitude * .pi / 180
        let lonScale = cos(midLatitudeRadians) * metersPerDegree

        var xs = [Double](); xs.reserveCapacity(points.count)
        var ys = [Double](); ys.reserveCapacity(points.count)
        for point in points {
            xs.append(point.longitude * lonScale)
            ys.append(point.latitude * metersPerDegree)
        }
        let kept = simplifyIndices(xs: xs, ys: ys, tolerance: toleranceMeters)
        return kept.map { points[$0] }
    }
}
