import AppKit
import Foundation
import os
import UserNotifications

/// Posts "Kliq is quiet" and "Kliq is back" when sleep changes, if the user asked for it.
///
/// Every notification reuses one identifier, so only the latest state is shown, and a
/// change is posted only after it has held for a moment, so flapping triggers stay silent.
/// Does nothing in unbundled debug runs, where UNUserNotificationCenter is unavailable.
@MainActor
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    /// Mirrors `Settings.notifyOnSleepChange`.
    var isEnabled = false
    /// Called after every permission check with whether notifications are turned off for Kliq.
    var onDeniedChange: ((Bool) -> Void)?

    private let center: UNUserNotificationCenter?
    /// The last settled sleep state; nil until the first one settles after launch.
    private var settled: Bool?
    private var pending: Task<Void, Never>?
    private var activeObserver: NSObjectProtocol?
    private let log = Logger(subsystem: "run.crafter.kliq", category: "notifications")

    private static let identifier = "run.crafter.kliq.sleep"
    private static let settleDelay: Duration = .milliseconds(1500)

    override init() {
        center = Bundle.main.bundleIdentifier == nil ? nil : UNUserNotificationCenter.current()
        super.init()
        guard let center else { return }
        center.delegate = self
        // Picks up a permission changed in System Settings when the user comes back to Kliq.
        activeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isEnabled else { return }
                self.refreshAuthorization()
            }
        }
    }

    /// Asks macOS for permission to post, which prompts only the first time.
    func requestAuthorization() {
        guard let center else { return }
        let log = self.log
        center.requestAuthorization(options: [.alert]) { [weak self] granted, error in
            if let error { log.error("Notification permission request failed: \(error.localizedDescription, privacy: .public)") }
            Task { @MainActor in self?.onDeniedChange?(!granted) }
        }
    }

    /// Reads the current permission without prompting.
    func refreshAuthorization() {
        checkAuthorization { _ in }
    }

    /// Call on every sleep change. The first state to settle after launch is only
    /// remembered; later ones post when they differ from it.
    func sleepChanged(sleeping: Bool, reasons: [String]) {
        guard center != nil else { return }
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(for: Self.settleDelay)
            guard !Task.isCancelled else { return }
            self?.settle(sleeping: sleeping, reasons: reasons)
        }
    }

    private func settle(sleeping: Bool, reasons: [String]) {
        let previous = settled
        settled = sleeping
        guard let previous, previous != sleeping, isEnabled else { return }
        checkAuthorization { [weak self] allowed in
            if allowed { self?.post(sleeping: sleeping, reasons: reasons) }
        }
    }

    private func post(sleeping: Bool, reasons: [String]) {
        guard let center else { return }
        let content = UNMutableNotificationContent()
        content.title = sleeping ? "Kliq is quiet" : "Kliq is back"
        if sleeping, !reasons.isEmpty {
            let text = reasons.joined(separator: ", ")
            content.body = text.prefix(1).uppercased() + text.dropFirst()
        }
        let log = self.log
        let request = UNNotificationRequest(identifier: Self.identifier, content: content, trigger: nil)
        center.add(request) { error in
            if let error { log.error("Posting a notification failed: \(error.localizedDescription, privacy: .public)") }
        }
    }

    private func checkAuthorization(_ completion: @escaping @MainActor (Bool) -> Void) {
        guard let center else { return }
        center.getNotificationSettings { [weak self] settings in
            let status = settings.authorizationStatus
            Task { @MainActor in
                self?.onDeniedChange?(status == .denied)
                completion(status == .authorized || status == .provisional)
            }
        }
    }

    // MARK: UNUserNotificationCenterDelegate

    /// Shows the banner even while a Kliq window is in front.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list])
    }
}
