import UIKit

/// Exists for one reason: `application(_:didFinishLaunchingWithOptions:)`
/// is the only place that receives the `.location` launch option when the
/// system relaunches the app after termination or reboot because a
/// significant-change (or region) event fired.
@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        let launchedForLocationEvent = launchOptions?[.location] != nil
        // Recreate the location manager and resume recording immediately —
        // before SwiftUI builds any UI — so queued fixes are not dropped.
        AppServices.shared.coordinator.handleLaunch(launchedForLocationEvent: launchedForLocationEvent)
        return true
    }
}
