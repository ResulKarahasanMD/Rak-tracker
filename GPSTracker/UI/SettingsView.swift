import SwiftUI
import TrackerKit

struct SettingsView: View {
    @Environment(RecordingCoordinator.self) private var coordinator
    @Environment(AppLockService.self) private var appLock

    @AppStorage(SettingsKeys.faceIDLockEnabled) private var faceIDEnabled = false
    @AppStorage(SettingsKeys.excludeFromBackup) private var excludeFromBackup = false
    @AppStorage(SettingsKeys.retentionDays) private var retentionDays = 0

    @State private var exportFrom = Calendar.current.date(byAdding: .day, value: -7, to: .now) ?? .now
    @State private var exportTo = Date.now
    @State private var exportFormat: ExportFormat = .gpx
    @State private var exportURL: URL?
    @State private var exportError: String?
    @State private var isExporting = false
    @State private var databaseSize: Int64 = 0
    @State private var pointCount = 0
    @State private var showDeleteConfirmation = false

    var body: some View {
        NavigationStack {
            Form {
                recordingSection
                exportSection
                privacySection
                storageSection
                aboutSection
            }
            .navigationTitle("Settings")
            .task { await refreshStats() }
        }
    }

    // MARK: Recording

    private var recordingSection: some View {
        Section {
            Toggle("Recording", isOn: Binding(
                get: { coordinator.isRecording },
                set: { enabled in
                    if enabled { coordinator.startRecording() } else { coordinator.stopRecording() }
                }
            ))
            Toggle("Precise mode", isOn: Binding(
                get: { coordinator.preciseModeEnabled },
                set: { coordinator.preciseModeEnabled = $0 }
            ))
            LabeledContent("Battery impact", value: batteryImpactText)
        } header: {
            Text("Recording")
        } footer: {
            Text("Precise mode uses best GPS accuracy with a 10 m filter (~3%/h battery). Off, the app adapts automatically: reduced accuracy while moving, GPS fully off while stationary.")
        }
    }

    private var batteryImpactText: String {
        guard coordinator.isRecording else { return "none (not recording)" }
        return String(format: "~%.1f%%/h now · ~%.0f–%.0f%% per day typical",
                      coordinator.estimatedPercentPerHour,
                      BatteryEstimator.estimateDailyPercent(hoursByMode: [.stationary: 20, .moving: 4]),
                      BatteryEstimator.estimateDailyPercent(hoursByMode: [.stationary: 16, .moving: 8]))
    }

    // MARK: Export

    private var exportSection: some View {
        Section {
            DatePicker("From", selection: $exportFrom, displayedComponents: .date)
            DatePicker("To", selection: $exportTo, displayedComponents: .date)
            Picker("Format", selection: $exportFormat) {
                ForEach(ExportFormat.allCases) { format in
                    Text(format.displayName).tag(format)
                }
            }
            Button {
                Task { await generateExport() }
            } label: {
                if isExporting {
                    ProgressView()
                } else {
                    Text("Generate export file")
                }
            }
            .disabled(isExporting)
            if let exportURL {
                ShareLink(item: exportURL) {
                    Label("Share \(exportURL.lastPathComponent)", systemImage: "square.and.arrow.up")
                }
            }
            if let exportError {
                Text(exportError).foregroundStyle(.red).font(.footnote)
            }
        } header: {
            Text("Export")
        } footer: {
            Text("GPX 1.1 imports into Dawarich, AdventureLog and most GPS tools. Files are generated locally and shared via the share sheet.")
        }
    }

    private func generateExport() async {
        isExporting = true
        exportError = nil
        exportURL = nil
        defer { isExporting = false }
        do {
            let calendar = Calendar.current
            let from = calendar.startOfDay(for: exportFrom)
            let toExclusive = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: exportTo)) ?? exportTo
            let points = try await coordinator.store.points(
                from: Int32(clamping: Int(from.timeIntervalSince1970)),
                to: Int32(clamping: Int(toExclusive.timeIntervalSince1970))
            )
            guard !points.isEmpty else {
                exportError = "No points in the selected range."
                return
            }
            let name = ExportEngine.defaultTrackName(from: from, to: exportTo)
            exportURL = try ExportEngine.writeExportFile(points: points, format: exportFormat, trackName: name)
        } catch {
            exportError = error.localizedDescription
        }
    }

    // MARK: Privacy

    private var privacySection: some View {
        Section {
            Toggle("Require Face ID", isOn: $faceIDEnabled)
                .onChange(of: faceIDEnabled) { _, enabled in
                    appLock.setEnabled(enabled)
                }
                .disabled(!AppLockService.isBiometryAvailable)
            Toggle("Exclude from iCloud backup", isOn: $excludeFromBackup)
                .onChange(of: excludeFromBackup) { _, excluded in
                    Task { await coordinator.store.setExcludedFromBackup(excluded) }
                }
        } header: {
            Text("Privacy")
        } footer: {
            Text("All data stays on this device. The app makes no network requests, has no analytics, and stores the database with iOS file protection.")
        }
    }

    // MARK: Storage

    private var storageSection: some View {
        Section {
            Picker("Keep data for", selection: $retentionDays) {
                Text("Forever").tag(0)
                Text("30 days").tag(30)
                Text("90 days").tag(90)
                Text("1 year").tag(365)
            }
            .onChange(of: retentionDays) { _, _ in
                coordinator.performMaintenance()
            }
            LabeledContent("Recorded points", value: "\(pointCount)")
            LabeledContent("Database size", value: ByteCountFormatter.string(fromByteCount: databaseSize, countStyle: .file))
            Button("Delete all data", role: .destructive) {
                showDeleteConfirmation = true
            }
            .confirmationDialog("Delete all recorded tracks?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
                Button("Delete everything", role: .destructive) {
                    Task {
                        try? await coordinator.store.deleteAllData()
                        await refreshStats()
                    }
                }
            }
        } header: {
            Text("Storage")
        } footer: {
            Text("Points cost ~25 bytes each; a full year of daily tracking stays well under 50 MB.")
        }
    }

    private func refreshStats() async {
        pointCount = (try? await coordinator.store.totalPointCount()) ?? 0
        databaseSize = await coordinator.store.databaseSizeBytes()
    }

    // MARK: About

    private var aboutSection: some View {
        Section("About") {
            LabeledContent("Network access", value: "None")
            LabeledContent("Analytics", value: "None")
            LabeledContent("Data location", value: "This device only")
        }
    }
}
