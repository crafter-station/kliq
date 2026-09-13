import Foundation
import Observation

/// Runtime state shown by the menu bar and settings UI.
@Observable
final class AppState {
    var accessibilityGranted = false
    var inputMonitoringActive = false
    var isSleeping = false
    var sleepReasons: [String] = []
    var availableSets: [SoundSet] = []
    var currentSetName = ""
    var statusMessage: String?
    /// The chosen shortcut could not be registered, usually because another app owns it.
    var hotKeyUnavailable = false
    /// The user turned on sleep notifications but macOS notifications are off for Kliq.
    var notificationsDenied = false
}
