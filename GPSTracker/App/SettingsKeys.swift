import Foundation

/// UserDefaults keys. Everything here is small preference state; all track
/// data lives in SQLite.
enum SettingsKeys {
    /// Recording was active; used to resume after termination/reboot relaunch.
    static let recordingActive = "recordingActive"
    /// User-enabled best-accuracy mode (never the default).
    static let preciseModeEnabled = "preciseModeEnabled"
    /// Require Face ID / passcode to open the app.
    static let faceIDLockEnabled = "faceIDLockEnabled"
    /// Exclude the database from iCloud/iTunes backups.
    static let excludeFromBackup = "excludeFromBackup"
    /// Auto-delete points older than this many days; 0 = keep forever.
    static let retentionDays = "retentionDays"
    /// Last tracking mode, restored on background relaunch.
    static let lastTrackingMode = "lastTrackingMode"
}
