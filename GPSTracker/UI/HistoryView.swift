import CoreLocation
import MapKit
import SwiftUI
import TrackerKit

/// History tab: one row per local day, with route rendering and stats.
struct HistoryView: View {
    @Environment(RecordingCoordinator.self) private var coordinator
    @State private var days: [DaySummary] = []
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            Group {
                if days.isEmpty {
                    ContentUnavailableView(
                        isLoading ? "Loading…" : "No recordings yet",
                        systemImage: "point.bottomleft.forward.to.point.topright.scurvepath",
                        description: Text(isLoading ? "" : "Start recording on the Map tab.")
                    )
                } else {
                    List(days) { day in
                        NavigationLink(value: day) {
                            DayRow(summary: day)
                        }
                    }
                    .navigationDestination(for: DaySummary.self) { day in
                        DayDetailView(summary: day)
                    }
                }
            }
            .navigationTitle("History")
            .task { await reload() }
            .refreshable { await reload() }
        }
    }

    private func reload() async {
        isLoading = true
        days = (try? await coordinator.store.daySummaries()) ?? []
        isLoading = false
    }
}

private struct DayRow: View {
    let summary: DaySummary

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(summary.startOfDayDate, style: .date)
                .font(.body.weight(.medium))
            Text("\(summary.pointCount) points · \(timeRange)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var timeRange: String {
        let first = Date(timeIntervalSince1970: TimeInterval(summary.firstTimestamp))
        let last = Date(timeIntervalSince1970: TimeInterval(summary.lastTimestamp))
        return "\(first.formatted(date: .omitted, time: .shortened)) – \(last.formatted(date: .omitted, time: .shortened))"
    }
}

/// Route + stats for one day. Loads the raw points for the day; falls back
/// to the pre-simplified track for very large days to keep rendering cheap.
private struct DayDetailView: View {
    @Environment(RecordingCoordinator.self) private var coordinator
    let summary: DaySummary

    @State private var points: [TrackPoint] = []
    @State private var exportURL: URL?

    var body: some View {
        VStack(spacing: 0) {
            Map {
                if coordinates.count > 1 {
                    MapPolyline(coordinates: coordinates)
                        .stroke(.blue, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                }
                if let start = coordinates.first {
                    Marker("Start", systemImage: "flag", coordinate: start)
                }
                if let end = coordinates.last, coordinates.count > 1 {
                    Marker("End", systemImage: "flag.checkered", coordinate: end)
                }
            }

            StatsBar(points: points)
        }
        .navigationTitle(summary.startOfDayDate.formatted(date: .abbreviated, time: .omitted))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if let exportURL {
                    ShareLink(item: exportURL) {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
        }
        .task { await load() }
    }

    private var coordinates: [CLLocationCoordinate2D] {
        points.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
    }

    private func load() async {
        let offset = TimeZone.current.secondsFromGMT()
        let from = Int32(clamping: summary.day * 86_400 - offset)
        let to = Int32(clamping: (summary.day + 1) * 86_400 - offset)
        var loaded = (try? await coordinator.store.points(from: from, to: to)) ?? []
        if loaded.count > 20_000 {
            let simplified = (try? await coordinator.store.simplifiedPoints(day: summary.day)) ?? []
            if !simplified.isEmpty { loaded = simplified }
        }
        points = loaded

        let name = summary.startOfDayDate.formatted(.iso8601.year().month().day())
        exportURL = try? ExportEngine.writeExportFile(points: loaded, format: .gpx, trackName: "track_\(name)")
    }
}

private struct StatsBar: View {
    let points: [TrackPoint]

    var body: some View {
        HStack {
            stat(value: distanceText, label: "Distance")
            Divider().frame(height: 28)
            stat(value: durationText, label: "Duration")
            Divider().frame(height: 28)
            stat(value: "\(points.count)", label: "Points")
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private func stat(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.subheadline.weight(.semibold))
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var distanceText: String {
        var meters = 0.0
        for i in 1..<max(points.count, 1) {
            meters += Haversine.distanceMeters(
                lat1: points[i - 1].latitude, lon1: points[i - 1].longitude,
                lat2: points[i].latitude, lon2: points[i].longitude
            )
        }
        return meters >= 1000
            ? String(format: "%.1f km", meters / 1000)
            : String(format: "%.0f m", meters)
    }

    private var durationText: String {
        guard let first = points.first, let last = points.last else { return "—" }
        let seconds = Int(last.timestamp - first.timestamp)
        return "\(seconds / 3600)h \(seconds % 3600 / 60)m"
    }
}
