import Foundation
import LocalAuthentication
import Observation

/// Optional Face ID / passcode gate in front of the UI. Purely local:
/// LocalAuthentication never leaves the device.
@MainActor
@Observable
final class AppLockService {
    private(set) var isLocked: Bool
    private(set) var lastError: String?

    var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: SettingsKeys.faceIDLockEnabled)
    }

    init() {
        isLocked = UserDefaults.standard.bool(forKey: SettingsKeys.faceIDLockEnabled)
    }

    static var isBiometryAvailable: Bool {
        var error: NSError?
        return LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)
    }

    /// Re-lock when the app leaves the foreground.
    func lockIfEnabled() {
        if isEnabled {
            isLocked = true
        }
    }

    func unlock() async {
        guard isLocked else { return }
        let context = LAContext()
        do {
            // .deviceOwnerAuthentication = Face ID with passcode fallback.
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: "Unlock your location history"
            )
            if success {
                isLocked = false
                lastError = nil
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    func setEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: SettingsKeys.faceIDLockEnabled)
        if !enabled {
            isLocked = false
        }
    }
}
