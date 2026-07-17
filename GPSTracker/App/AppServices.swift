import Foundation

/// Composition root. A single instance shared by the `UIApplicationDelegate`
/// (background relaunch path) and the SwiftUI scene (UI path).
@MainActor
final class AppServices {
    static let shared = AppServices()

    let coordinator: RecordingCoordinator
    let appLock: AppLockService

    private init() {
        coordinator = RecordingCoordinator()
        appLock = AppLockService()
    }
}
