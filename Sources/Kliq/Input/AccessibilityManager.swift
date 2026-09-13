import AppKit
import ApplicationServices
import Foundation

/// Tracks the Accessibility (event tap) permission and prompts for it.
///
/// Polls only while permission is missing, so onboarding reacts as soon as it is
/// granted. Once trusted it stops polling and relies on the system's accessibility
/// notification to notice a revocation, then polls again until trust returns.
@MainActor
final class AccessibilityManager: NSObject {
    private(set) var isTrusted: Bool = AXIsProcessTrusted()
    var onChange: ((Bool) -> Void)?
    private var timer: Timer?
    private var interval: TimeInterval = 1.0
    private var monitoring = false
    private var recheck: Task<Void, Never>?

    private static let trustChanged = Notification.Name("com.apple.accessibility.api")

    /// Shows the system prompt if permission has not been granted yet.
    func requestAccess() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let trusted = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
        update(trusted)
    }

    /// Clears Kliq's Accessibility entry, then asks again. macOS keeps one entry per
    /// app; when it was granted to an earlier signature of Kliq the system neither
    /// applies it nor shows the prompt again, so resetting lets the prompt appear.
    func resetAndRequest() {
        let bundleID = Bundle.main.bundleIdentifier ?? "run.crafter.kliq"
        Task.detached { [weak self] in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
            process.arguments = ["reset", "Accessibility", bundleID]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try? process.run()
            process.waitUntilExit()
            await self?.requestAccess()
        }
    }

    func startPolling(interval: TimeInterval = 1.0) {
        self.interval = interval
        timer?.invalidate()
        timer = nil
        if !monitoring {
            monitoring = true
            // Deliver immediately: Kliq is rarely the active app, and by default
            // distributed notifications are held until it becomes active.
            DistributedNotificationCenter.default().addObserver(
                self, selector: #selector(trustListChanged), name: Self.trustChanged,
                object: nil, suspensionBehavior: .deliverImmediately)
        }
        updatePolling()
    }

    func stopPolling() {
        monitoring = false
        DistributedNotificationCenter.default().removeObserver(self)
        recheck?.cancel()
        recheck = nil
        updatePolling()
    }

    func refresh() {
        update(AXIsProcessTrusted())
    }

    func openSystemSettings() {
        let urls = [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
        ]
        for string in urls {
            if let url = URL(string: string), NSWorkspace.shared.open(url) { return }
        }
    }

    private func update(_ trusted: Bool) {
        guard trusted != isTrusted else { return }
        isTrusted = trusted
        updatePolling()
        onChange?(trusted)
    }

    /// Runs the timer only while monitoring and not trusted.
    private func updatePolling() {
        guard monitoring, !isTrusted else {
            timer?.invalidate()
            timer = nil
            return
        }
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }
    }

    /// Posted when any app's Accessibility grant changes. TCC applies the change
    /// asynchronously, so check again about 0.5 s and 2 s later.
    @objc nonisolated private func trustListChanged() {
        Task { @MainActor [weak self] in self?.scheduleRecheck() }
    }

    private func scheduleRecheck() {
        recheck?.cancel()
        recheck = Task { [weak self] in
            for delay in [Duration.milliseconds(500), .milliseconds(1500)] {
                try? await Task.sleep(for: delay)
                guard !Task.isCancelled else { return }
                self?.refresh()
            }
        }
    }
}
