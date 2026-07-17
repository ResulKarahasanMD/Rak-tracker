import SwiftUI

@main
struct GPSTrackerApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase

    private let services = AppServices.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(services.coordinator)
                .environment(services.appLock)
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active:
                services.coordinator.performMaintenance()
            case .background:
                // Persist buffered points before execution time runs out;
                // recording itself continues via the location background mode.
                services.coordinator.flushSoon()
                services.appLock.lockIfEnabled()
            default:
                break
            }
        }
    }
}
