import CoreLocation
import MapKit
import SwiftUI
import UIKit

/// Live map tab: Apple Maps only, no tile downloads beyond what MapKit
/// itself manages. Shows the user position, today's recorded path, the
/// persistent recording indicator, and the start/stop control.
struct LiveMapView: View {
    @Environment(RecordingCoordinator.self) private var coordinator
    @State private var cameraPosition: MapCameraPosition = .userLocation(fallback: .automatic)

    var body: some View {
        ZStack(alignment: .top) {
            Map(position: $cameraPosition) {
                UserAnnotation()
                if coordinator.livePathCoordinates.count > 1 {
                    MapPolyline(coordinates: coordinator.livePathCoordinates)
                        .stroke(.blue, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                }
            }
            .mapControls {
                MapUserLocationButton()
                MapCompass()
                MapScaleView()
            }

            VStack(spacing: 10) {
                RecordingIndicator()
                if coordinator.needsAlwaysUpgrade {
                    AlwaysUpgradeBanner()
                }
                if coordinator.authorizationStatus == .denied || coordinator.authorizationStatus == .restricted {
                    PermissionDeniedBanner()
                }
            }
            .padding(.top, 8)
        }
        .safeAreaInset(edge: .bottom) {
            RecordButton()
                .padding(.bottom, 8)
        }
        .onAppear {
            if coordinator.authorizationStatus == .notDetermined {
                coordinator.requestInitialPermission()
            } else if !coordinator.isRecording {
                coordinator.requestSingleLocation()
            }
        }
    }
}

private struct RecordButton: View {
    @Environment(RecordingCoordinator.self) private var coordinator

    var body: some View {
        Button {
            if coordinator.isRecording {
                coordinator.stopRecording()
            } else {
                coordinator.startRecording()
            }
        } label: {
            Label(
                coordinator.isRecording ? "Stop Recording" : "Start Recording",
                systemImage: coordinator.isRecording ? "stop.circle.fill" : "record.circle"
            )
            .font(.headline)
            .padding(.horizontal, 20)
            .padding(.vertical, 6)
        }
        .buttonStyle(.borderedProminent)
        .tint(coordinator.isRecording ? .red : .accentColor)
        .disabled(coordinator.authorizationStatus == .denied || coordinator.authorizationStatus == .restricted)
    }
}

/// Explains why Always access matters before triggering the system upgrade
/// prompt (When-In-Use was already granted at this point).
private struct AlwaysUpgradeBanner: View {
    @Environment(RecordingCoordinator.self) private var coordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Allow background recording")
                .font(.subheadline.weight(.semibold))
            Text("To keep recording while the app is closed or the phone is locked, allow location access \u{201C}Always\u{201D}. Your data never leaves this device.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Allow Always Access") {
                coordinator.requestAlwaysUpgrade()
            }
            .font(.caption.weight(.semibold))
        }
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }
}

private struct PermissionDeniedBanner: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Location access denied")
                .font(.subheadline.weight(.semibold))
            Text("Enable location access in Settings to record tracks.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let url = URL(string: UIApplication.openSettingsURLString) {
                Link("Open Settings", destination: url)
                    .font(.caption.weight(.semibold))
            }
        }
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }
}
