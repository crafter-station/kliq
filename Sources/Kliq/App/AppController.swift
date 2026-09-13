import AppKit
import Foundation
import Observation
import os

/// Owns every subsystem and wires settings changes through to them.
@Observable @MainActor
final class AppController {
    let settings = Settings.shared
    let state = AppState()
    let stats = StatsManager()
    let accessibility = AccessibilityManager()
    let engine = SoundEngine()
    let sleep = SleepManager()
    let outputDevices = AudioOutputDevices()

    @ObservationIgnored private let input = InputMonitor()
    @ObservationIgnored private let hotKey = HotKeyManager()
    @ObservationIgnored private let notifier = Notifier()
    @ObservationIgnored private var recordingHotKey = false
    @ObservationIgnored private var statusMenu: StatusMenuController?
    @ObservationIgnored private var settingsWindow: HostedWindowController?
    @ObservationIgnored private var onboardingWindow: HostedWindowController?
    @ObservationIgnored private var loadedSetName: String?
    @ObservationIgnored private var previewWhenLoaded = false
    @ObservationIgnored private let log = Logger(subsystem: "run.crafter.kliq", category: "app")
    @ObservationIgnored private let firstEventSeen = OSAllocatedUnfairLock(initialState: false)

    /// The mellowest bundled set, chosen until the user picks another one.
    private static let defaultSetName = "Synth Thock"
    private static let noSoundsMessage = "Kliq couldn't find its sounds. Reinstalling Kliq should bring them back."

    // MARK: Lifecycle

    func start() {
        if engine.start() {
            log.notice("Audio engine started")
        } else {
            log.error("Audio engine failed to start; it retries on the next sound")
        }

        engine.onPlayed = { [weak self] played in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.stats.record(played, setName: self.state.currentSetName)
            }
        }
        sleep.onChange = { [weak self] in self?.sleepStateChanged() }
        hotKey.onPressed = { [weak self] in self?.toggleEnabled() }
        accessibility.onChange = { [weak self] trusted in self?.accessibilityChanged(trusted) }
        notifier.onDeniedChange = { [weak self] denied in
            guard let self else { return }
            self.state.notificationsDenied = denied && self.settings.notifyOnSleepChange
        }

        state.accessibilityGranted = accessibility.isTrusted
        log.notice("Accessibility trusted at launch: \(self.accessibility.isTrusted)")
        accessibility.startPolling()
        outputDevices.start()
        rescanSets()
        statusMenu = StatusMenuController(controller: self)
        bindSettings()

        if accessibility.isTrusted {
            startInputMonitoring()
            if !settings.hasCompletedOnboarding { showOnboarding() }
        } else {
            showOnboarding()
        }
    }

    func shutdown() {
        stats.flush()
        input.stop()
        sleep.stopAll()
        hotKey.unregister()
        accessibility.stopPolling()
        engine.stop()
    }

    // MARK: Actions

    func toggleEnabled() {
        settings.isEnabled.toggle()
    }

    /// With `preview`, plays the set once it has loaded, like choosing an alert sound.
    func selectSet(named name: String, preview: Bool = false) {
        settings.selectedSetName = name
        guard preview else { return }
        if state.currentSetName == name { engine.preview() } else { previewWhenLoaded = true }
    }

    func wake() {
        sleep.wake()
    }

    func previewCurrentSet() {
        engine.preview()
    }

    /// Suspends the global shortcut while Settings records a new one, so pressing
    /// the current combination doesn't toggle sound mid-recording.
    func setHotKeyRecording(_ recording: Bool) {
        recordingHotKey = recording
        if recording { hotKey.unregister() } else { applyHotKey() }
    }

    /// Asks macOS for permission to post sleep notifications.
    func requestNotificationPermission() {
        notifier.requestAuthorization()
    }

    func rescanSets() {
        let sets = SoundLibrary.discover()
        state.availableSets = sets
        if !sets.contains(where: { $0.name == settings.selectedSetName }),
           let fallback = sets.first(where: { $0.name == Self.defaultSetName }) ?? sets.first {
            settings.selectedSetName = fallback.name
        }
        if sets.isEmpty {
            state.statusMessage = Self.noSoundsMessage
        } else if state.statusMessage == Self.noSoundsMessage {
            state.statusMessage = nil
        }
    }

    func showSettings() {
        if settingsWindow == nil {
            settingsWindow = HostedWindowController(title: "Kliq Settings") { [unowned self] in
                SettingsRootView()
                    .environment(self)
                    .environment(self.state)
                    .environment(self.settings)
                    .environment(self.stats)
                    .environment(self.outputDevices)
            }
        }
        settingsWindow?.show()
    }

    func showOnboarding() {
        if onboardingWindow == nil {
            onboardingWindow = HostedWindowController(title: "Welcome to Kliq") { [unowned self] in
                OnboardingView { [weak self] in self?.finishOnboarding() }
                    .environment(self)
                    .environment(self.state)
                    .environment(self.settings)
            }
        }
        onboardingWindow?.show()
    }

    func finishOnboarding() {
        settings.hasCompletedOnboarding = true
        onboardingWindow?.close()
    }

    // MARK: Wiring

    private func bindSettings() {
        observeChanges { [weak self] in self?.applyPlaybackConfig() }
        observeChanges { [weak self] in self?.applySleepTriggers() }
        observeChanges { [weak self] in self?.applyHotKey() }
        observeChanges { [weak self] in self?.applySelectedSet() }
        observeChanges { [weak self] in self?.applyOutputDevice() }
        observeChanges { [weak self] in self?.applyNotifications() }
        observeChanges { [weak self] in self?.statusMenu?.refreshIcon() }
    }

    private func applyPlaybackConfig() {
        let sleeping = state.isSleeping
        let sleepGain = Float(settings.sleepVolume)
        engine.masterVolume = Float(settings.volume) * (sleeping ? sleepGain : 1)
        log.debug("Playback config: enabled=\(self.settings.isEnabled) sleeping=\(sleeping) volume=\(self.settings.volume)")
        engine.update(config: SoundEngine.Config(
            enabled: settings.isEnabled,
            muted: sleeping && settings.sleepVolume <= 0.001,
            effectsGain: Float(settings.effectsVolume),
            pitchVariation: settings.pitchVariation,
            stereoPanning: settings.stereoPanning,
            audibleModifiers: settings.audibleModifierKeys,
            ignoreKeyRepeat: settings.ignoreKeyRepeat,
            mouseClicks: settings.playMouseClicks,
            dingOnReturn: settings.playDingOnReturn,
            pitchShift: Float(settings.tonePitch),
            brightness: Float(settings.toneBrightness)))
    }

    private func applySleepTriggers() {
        var triggers = Set<SleepManager.Trigger>()
        if settings.sleepOnMicrophone { triggers.insert(.microphone) }
        if settings.sleepOnCamera { triggers.insert(.camera) }
        if settings.sleepOnNowPlaying { triggers.insert(.nowPlaying) }
        sleep.configure(enabled: triggers)
    }

    private func applyHotKey() {
        // Read before the recording check so a new combo still reruns this.
        let combo = settings.hotKey
        guard !recordingHotKey else { return }
        let registered = hotKey.configure(combo.map { ($0.keyCode, $0.modifiers) })
        state.hotKeyUnavailable = combo != nil && !registered
        if let combo, !registered {
            log.error("Shortcut \(combo.label, privacy: .public) could not be registered")
        }
    }

    private func applyOutputDevice() {
        // Reading the list reruns this as devices come and go, so a missing device is
        // picked up again when it returns.
        _ = outputDevices.devices
        engine.setOutputDevice(uid: settings.outputDeviceUID)
    }

    private func applyNotifications() {
        let on = settings.notifyOnSleepChange
        notifier.isEnabled = on
        // Only reads the permission; the prompt comes from requestNotificationPermission().
        if on { notifier.refreshAuthorization() } else { state.notificationsDenied = false }
    }

    private func applySelectedSet() {
        let sets = state.availableSets
        let wanted = settings.selectedSetName
        guard let set = sets.first(where: { $0.name == wanted }) ?? sets.first else { return }
        loadSet(set)
    }

    private func loadSet(_ set: SoundSet) {
        guard set.name != loadedSetName else { return }
        loadedSetName = set.name
        engine.load(set: set) { [weak self] count in
            guard let self else { return }
            self.state.currentSetName = set.name
            self.state.statusMessage = count == 0 ? "Kliq couldn't play \(set.displayName). Choose another switch set." : nil
            if self.previewWhenLoaded {
                self.previewWhenLoaded = false
                if count > 0 { self.engine.preview() }
            }
            self.log.notice("Loaded set \(set.name, privacy: .public): \(count) key samples")
        }
    }

    private func sleepStateChanged() {
        state.isSleeping = sleep.isSleeping
        state.sleepReasons = sleep.reasons
        log.notice("Sleep state: \(self.sleep.isSleeping) reasons: \(self.sleep.reasons.joined(separator: ", "), privacy: .public)")
        notifier.sleepChanged(sleeping: sleep.isSleeping, reasons: sleep.reasons)
    }

    private func accessibilityChanged(_ trusted: Bool) {
        state.accessibilityGranted = trusted
        log.notice("Accessibility trust changed: \(trusted)")
        if trusted {
            startInputMonitoring()
        } else {
            input.stop()
            state.inputMonitoringActive = false
        }
    }

    private func startInputMonitoring() {
        guard !input.isRunning else { return }
        let engine = self.engine
        let log = self.log
        let firstEventSeen = self.firstEventSeen
        input.handler = { event in
            if firstEventSeen.withLock({ seen in defer { seen = true }; return !seen }) {
                log.notice("First input event received by the tap")
            }
            engine.handle(event)
        }
        let ok = input.start()
        state.inputMonitoringActive = ok
        log.notice("Event tap start: \(ok)")
        if !ok {
            state.statusMessage = "Kliq can't listen for key presses. Check that Kliq is turned on in System Settings → Privacy & Security → Accessibility."
        }
    }
}
