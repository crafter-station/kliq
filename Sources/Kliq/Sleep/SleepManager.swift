import Foundation

/// Aggregates the sleep triggers. When any enabled trigger is active the app
/// "sleeps" (mutes or attenuates) until every trigger clears or the user wakes it.
@MainActor
final class SleepManager {
    enum Trigger: String, CaseIterable, Hashable {
        case microphone
        case camera
        case nowPlaying

        var reason: String {
            switch self {
            case .microphone: return "microphone in use"
            case .camera: return "camera in use"
            case .nowPlaying: return "music playing"
            }
        }
    }

    var onChange: (() -> Void)?
    private(set) var enabled: Set<Trigger> = []
    private(set) var active: Set<Trigger> = []
    private var snoozed = false

    private let microphone = MicrophoneMonitor()
    private let camera = CameraMonitor()
    private let nowPlaying = NowPlayingMonitor()

    init() {
        microphone.onChange = { [weak self] on in self?.set(.microphone, on) }
        camera.onChange = { [weak self] on in self?.set(.camera, on) }
        nowPlaying.onChange = { [weak self] on in self?.set(.nowPlaying, on) }
    }

    var isSleeping: Bool {
        !snoozed && !active.intersection(enabled).isEmpty
    }

    var reasons: [String] {
        Trigger.allCases.filter { active.contains($0) && enabled.contains($0) }.map(\.reason)
    }

    func configure(enabled newValue: Set<Trigger>) {
        guard newValue != enabled else { return }
        enabled = newValue
        newValue.contains(.microphone) ? microphone.start() : microphone.stop()
        newValue.contains(.camera) ? camera.start() : camera.stop()
        newValue.contains(.nowPlaying) ? nowPlaying.start() : nowPlaying.stop()
        if active.intersection(enabled).isEmpty { snoozed = false }
        onChange?()
    }

    /// Ignores the current triggers until they all clear.
    func wake() {
        guard isSleeping else { return }
        snoozed = true
        onChange?()
    }

    func stopAll() {
        microphone.stop()
        camera.stop()
        nowPlaying.stop()
    }

    private func set(_ trigger: Trigger, _ on: Bool) {
        let before = (isSleeping, reasons)
        if on { active.insert(trigger) } else { active.remove(trigger) }
        if active.intersection(enabled).isEmpty { snoozed = false }
        let after = (isSleeping, reasons)
        if before != after { onChange?() }
    }
}
