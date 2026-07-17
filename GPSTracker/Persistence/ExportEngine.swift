import Foundation
import TrackerKit

enum ExportFormat: String, CaseIterable, Identifiable {
    case gpx
    case geojson
    case csv

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .gpx: "GPX 1.1"
        case .geojson: "GeoJSON"
        case .csv: "CSV"
        }
    }

    var fileExtension: String {
        switch self {
        case .gpx: "gpx"
        case .geojson: "geojson"
        case .csv: "csv"
        }
    }
}

/// Renders track points into an export file in the temporary directory,
/// ready to hand to a share sheet / Files. No networking involved.
enum ExportEngine {
    static func writeExportFile(
        points: [TrackPoint],
        format: ExportFormat,
        trackName: String
    ) throws -> URL {
        let content: String
        switch format {
        case .gpx:
            content = GPXExporter.export(points: points, trackName: trackName)
        case .geojson:
            content = GeoJSONExporter.export(points: points, name: trackName)
        case .csv:
            content = CSVExporter.export(points: points)
        }

        let safeName = trackName.map { $0.isLetter || $0.isNumber || $0 == "-" ? $0 : "_" }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(String(safeName))
            .appendingPathExtension(format.fileExtension)
        try content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    /// Suggested file name for a date-range export, e.g. "track_2026-07-01_2026-07-17".
    static func defaultTrackName(from: Date, to: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return "track_\(formatter.string(from: from))_\(formatter.string(from: to))"
    }
}
