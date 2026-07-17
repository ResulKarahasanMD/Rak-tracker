import CoreMotion
import Foundation
import TrackerKit

/// Streams `CMMotionActivity` classifications as `EnergyPolicy` evidence.
/// The motion coprocessor does this classification at negligible power cost,
/// which is what lets the app keep GPS off while the user is stationary.
@MainActor
final class MotionActivityService {
    var onEvidence: (@MainActor (EnergyPolicy.Evidence) -> Void)?

    /// Most recent classification, attached to every stored point.
    private(set) var currentActivity: ActivityFlag = .unknown
    /// Most recent evidence, re-fed periodically by the coordinator because
    /// CMMotionActivityManager only pushes updates when the activity changes.
    private(set) var lastEvidence: EnergyPolicy.Evidence?

    private let manager = CMMotionActivityManager()
    private var isRunning = false

    static var isAvailable: Bool {
        CMMotionActivityManager.isActivityAvailable()
    }

    func start() {
        guard !isRunning, Self.isAvailable else { return }
        isRunning = true
        manager.startActivityUpdates(to: .main) { [weak self] activity in
            guard let self, let activity else { return }
            MainActor.assumeIsolated {
                self.handle(activity)
            }
        }
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        manager.stopActivityUpdates()
        currentActivity = .unknown
        lastEvidence = nil
    }

    private func handle(_ activity: CMMotionActivity) {
        let flag = Self.activityFlag(from: activity)
        if flag != .unknown {
            currentActivity = flag
        }
        let evidence = EnergyPolicy.Evidence(
            activity: flag,
            confidence: Self.confidence(from: activity.confidence),
            speedMps: nil,
            timestamp: Date().timeIntervalSince1970
        )
        lastEvidence = evidence
        onEvidence?(evidence)
    }

    private static func activityFlag(from activity: CMMotionActivity) -> ActivityFlag {
        // CMMotionActivity flags are not mutually exclusive; prefer the most
        // power-relevant (fastest) classification.
        if activity.automotive { return .automotive }
        if activity.cycling { return .cycling }
        if activity.running { return .running }
        if activity.walking { return .walking }
        if activity.stationary { return .stationary }
        return .unknown
    }

    private static func confidence(from confidence: CMMotionActivityConfidence) -> EnergyPolicy.Confidence {
        switch confidence {
        case .low: .low
        case .medium: .medium
        case .high: .high
        @unknown default: .low
        }
    }
}
