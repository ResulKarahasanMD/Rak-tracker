import SwiftUI
import TrackerKit

/// Persistent pill shown on the live map while recording: current mode,
/// point count, and the estimated battery impact of the current duty cycle.
struct RecordingIndicator: View {
    @Environment(RecordingCoordinator.self) private var coordinator

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(coordinator.isRecording ? Color.red : Color.gray)
                .frame(width: 10, height: 10)
                .opacity(coordinator.isRecording ? 1 : 0.5)
            VStack(alignment: .leading, spacing: 1) {
                Text(statusText)
                    .font(.caption.weight(.semibold))
                if coordinator.isRecording {
                    Text(detailText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.thinMaterial, in: Capsule())
    }

    private var statusText: String {
        guard coordinator.isRecording else { return "Not recording" }
        return switch coordinator.mode {
        case .stationary: "Recording — stationary, GPS off"
        case .moving: "Recording — \(coordinator.currentActivity.label)"
        case .precise: "Recording — precise mode"
        }
    }

    private var detailText: String {
        let drain = coordinator.estimatedPercentPerHour
        return "\(coordinator.sessionPointCount) pts · ~\(String(format: "%.1f", drain))%/h battery"
    }
}
