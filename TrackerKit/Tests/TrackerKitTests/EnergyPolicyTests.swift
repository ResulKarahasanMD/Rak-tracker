import Testing
@testable import TrackerKit

@Suite("EnergyPolicy state machine")
struct EnergyPolicyTests {
    private func makePolicy() -> EnergyPolicy {
        EnergyPolicy(config: .init(stationaryDebounceSeconds: 180, movingSpeedThresholdMps: 0.5))
    }

    @Test func startsInMovingModeToAcquireFirstFix() {
        #expect(makePolicy().mode == .moving)
    }

    @Test func walkingActivityKeepsMovingMode() {
        var policy = makePolicy()
        let mode = policy.process(.init(activity: .walking, confidence: .high, speedMps: 1.4, timestamp: 0))
        #expect(mode == .moving)
    }

    @Test func stationaryRequiresDebounceBeforeSwitching() {
        var policy = makePolicy()
        // First stationary evidence: still moving (debounce running).
        #expect(policy.process(.init(activity: .stationary, confidence: .high, speedMps: 0, timestamp: 0)) == .moving)
        // 60 s later: still within debounce window.
        #expect(policy.process(.init(activity: .stationary, confidence: .high, speedMps: 0, timestamp: 60)) == .moving)
        // 180 s of continuous stationary evidence: switch to stationary.
        #expect(policy.process(.init(activity: .stationary, confidence: .high, speedMps: 0, timestamp: 180)) == .stationary)
    }

    @Test func movementCancelsStationaryDebounce() {
        var policy = makePolicy()
        _ = policy.process(.init(activity: .stationary, confidence: .high, speedMps: 0, timestamp: 0))
        _ = policy.process(.init(activity: .walking, confidence: .high, speedMps: 1.2, timestamp: 90))
        // Stationary evidence restarts from scratch; 179 s is not enough.
        _ = policy.process(.init(activity: .stationary, confidence: .high, speedMps: 0, timestamp: 100))
        #expect(policy.process(.init(activity: .stationary, confidence: .high, speedMps: 0, timestamp: 279)) == .moving)
        #expect(policy.process(.init(activity: .stationary, confidence: .high, speedMps: 0, timestamp: 280)) == .stationary)
    }

    @Test func movementWakesFromStationaryImmediately() {
        var policy = makePolicy()
        _ = policy.process(.init(activity: .stationary, confidence: .high, speedMps: 0, timestamp: 0))
        _ = policy.process(.init(activity: .stationary, confidence: .high, speedMps: 0, timestamp: 180))
        #expect(policy.mode == .stationary)
        #expect(policy.process(.init(activity: .automotive, confidence: .medium, speedMps: nil, timestamp: 200)) == .moving)
    }

    @Test func speedAloneCountsAsMovementEvidence() {
        var policy = makePolicy()
        _ = policy.process(.init(activity: .stationary, confidence: .high, speedMps: 0, timestamp: 0))
        _ = policy.process(.init(activity: .stationary, confidence: .high, speedMps: 0, timestamp: 180))
        #expect(policy.mode == .stationary)
        // Motion chip says stationary but GPS speed says driving (e.g. phone mounted in car).
        #expect(policy.process(.init(activity: .stationary, confidence: .high, speedMps: 8, timestamp: 300)) == .moving)
    }

    @Test func lowConfidenceEvidenceIsIgnored() {
        var policy = makePolicy()
        _ = policy.process(.init(activity: .stationary, confidence: .low, speedMps: nil, timestamp: 0))
        _ = policy.process(.init(activity: .stationary, confidence: .low, speedMps: nil, timestamp: 400))
        #expect(policy.mode == .moving, "low-confidence stationary reports must not turn GPS off")
    }

    @Test func preciseModeOverridesEverything() {
        var policy = makePolicy()
        policy.preciseEnabled = true
        #expect(policy.process(.init(activity: .stationary, confidence: .high, speedMps: 0, timestamp: 0)) == .precise)
        #expect(policy.process(.init(activity: .stationary, confidence: .high, speedMps: 0, timestamp: 1000)) == .precise)
        // Disabling precise falls back to the underlying adaptive mode.
        policy.preciseEnabled = false
        #expect(policy.process(.init(activity: .walking, confidence: .high, speedMps: 1.2, timestamp: 1010)) == .moving)
    }

    @Test func profilesMatchEnergyDesign() {
        let stationary = EnergyPolicy.profile(for: .stationary)
        #expect(stationary.usesContinuousGPS == false)

        let moving = EnergyPolicy.profile(for: .moving)
        #expect(moving.usesContinuousGPS == true)
        #expect(moving.accuracy == .hundredMeters)
        #expect(moving.distanceFilterMeters == 75)

        let precise = EnergyPolicy.profile(for: .precise)
        #expect(precise.usesContinuousGPS == true)
        #expect(precise.accuracy == .best)
        #expect(precise.distanceFilterMeters == 10)
    }

    @Test func batteryEstimatesAreOrderedByPower() {
        let stationary = BatteryEstimator.percentPerHour(for: .stationary)
        let moving = BatteryEstimator.percentPerHour(for: .moving)
        let precise = BatteryEstimator.percentPerHour(for: .precise)
        #expect(stationary < moving)
        #expect(moving < precise)
        // 24 h of typical use (mostly stationary, some movement) must fit the 5–8 % budget.
        let typicalDay = stationary * 20 + moving * 4
        #expect(typicalDay <= 8.0, "typical day estimate \(typicalDay)% exceeds budget")
    }
}
