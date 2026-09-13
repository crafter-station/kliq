import Foundation
import ServiceManagement

/// Launch-at-login via SMAppService. Only works when running from a .app bundle.
enum LaunchAtLogin {
    /// On once registered, including while the login item awaits approval.
    static var isEnabled: Bool {
        switch SMAppService.mainApp.status {
        case .enabled, .requiresApproval: return true
        default: return false
        }
    }

    /// Registered, but the user still has to allow it in System Settings > Login Items.
    static var isAwaitingApproval: Bool {
        SMAppService.mainApp.status == .requiresApproval
    }

    static func set(_ enabled: Bool) throws {
        let service = SMAppService.mainApp
        guard enabled else {
            try service.unregister()
            return
        }
        do {
            try service.register()
        } catch {
            // A login item the user has to approve first stays registered; not a failure.
            guard service.status == .requiresApproval else { throw error }
        }
        if service.status == .requiresApproval {
            SMAppService.openSystemSettingsLoginItems()
        }
    }
}
