import Foundation
import Observation

/// User preferences. Every property writes through to UserDefaults on change.
@Observable
final class Settings {
    static let shared = Settings()

    private enum Key {
        static let isEnabled = "isEnabled"
        static let volume = "volume"
        static let effectsVolume = "effectsVolume"
        static let selectedSetName = "selectedSetName"
        static let pitchVariation = "pitchVariation"
        static let stereoPanning = "stereoPanning"
        static let audibleModifierKeys = "audibleModifierKeys"
        static let ignoreKeyRepeat = "ignoreKeyRepeat"
        static let playMouseClicks = "playMouseClicks"
        static let playDingOnReturn = "playDingOnReturn"
        static let sleepOnMicrophone = "sleepOnMicrophone"
        static let sleepOnCamera = "sleepOnCamera"
        static let sleepOnNowPlaying = "sleepOnNowPlaying"
        static let sleepVolume = "sleepVolume"
        static let hotKey = "hotKey"
        static let dimMenuBarIconWhenOff = "dimMenuBarIconWhenOff"
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
        static let outputDeviceUID = "outputDeviceUID"
        static let tonePitch = "tonePitch"
        static let toneBrightness = "toneBrightness"
        static let notifyOnSleepChange = "notifyOnSleepChange"
    }

    var isEnabled: Bool { didSet { store.set(isEnabled, forKey: Key.isEnabled) } }
    var volume: Double { didSet { store.set(volume, forKey: Key.volume) } }
    var effectsVolume: Double { didSet { store.set(effectsVolume, forKey: Key.effectsVolume) } }
    var selectedSetName: String { didSet { store.set(selectedSetName, forKey: Key.selectedSetName) } }
    var pitchVariation: Bool { didSet { store.set(pitchVariation, forKey: Key.pitchVariation) } }
    var stereoPanning: Bool { didSet { store.set(stereoPanning, forKey: Key.stereoPanning) } }
    var audibleModifierKeys: Bool { didSet { store.set(audibleModifierKeys, forKey: Key.audibleModifierKeys) } }
    var ignoreKeyRepeat: Bool { didSet { store.set(ignoreKeyRepeat, forKey: Key.ignoreKeyRepeat) } }
    var playMouseClicks: Bool { didSet { store.set(playMouseClicks, forKey: Key.playMouseClicks) } }
    var playDingOnReturn: Bool { didSet { store.set(playDingOnReturn, forKey: Key.playDingOnReturn) } }
    var sleepOnMicrophone: Bool { didSet { store.set(sleepOnMicrophone, forKey: Key.sleepOnMicrophone) } }
    var sleepOnCamera: Bool { didSet { store.set(sleepOnCamera, forKey: Key.sleepOnCamera) } }
    var sleepOnNowPlaying: Bool { didSet { store.set(sleepOnNowPlaying, forKey: Key.sleepOnNowPlaying) } }
    /// Gain applied while sleeping, 0 = silent, 1 = no change.
    var sleepVolume: Double { didSet { store.set(sleepVolume, forKey: Key.sleepVolume) } }
    /// Global shortcut that turns sounds on and off, or nil for none.
    var hotKey: HotKeyCombo? { didSet { store.set(hotKey?.storageValue ?? "off", forKey: Key.hotKey) } }
    var dimMenuBarIconWhenOff: Bool { didSet { store.set(dimMenuBarIconWhenOff, forKey: Key.dimMenuBarIconWhenOff) } }
    var hasCompletedOnboarding: Bool { didSet { store.set(hasCompletedOnboarding, forKey: Key.hasCompletedOnboarding) } }
    /// Core Audio UID of the output device, or "" to follow the system output.
    var outputDeviceUID: String { didSet { store.set(outputDeviceUID, forKey: Key.outputDeviceUID) } }
    /// Pitch of every key, -1...1 (about three semitones down or up). 0 plays samples as recorded.
    var tonePitch: Double { didSet { store.set(tonePitch, forKey: Key.tonePitch) } }
    /// Tilts the sound darker (-1) or brighter (+1). 0 leaves it untouched.
    var toneBrightness: Double { didSet { store.set(toneBrightness, forKey: Key.toneBrightness) } }
    /// Posts a notification when Kliq goes quiet or wakes up.
    var notifyOnSleepChange: Bool { didSet { store.set(notifyOnSleepChange, forKey: Key.notifyOnSleepChange) } }

    @ObservationIgnored private let store: UserDefaults

    private init(store: UserDefaults = .standard) {
        self.store = store
        isEnabled = store.bool(Key.isEnabled, default: true)
        volume = store.double(Key.volume, default: 0.7)
        effectsVolume = store.double(Key.effectsVolume, default: 0.8)
        selectedSetName = store.string(forKey: Key.selectedSetName) ?? ""
        pitchVariation = store.bool(Key.pitchVariation, default: true)
        stereoPanning = store.bool(Key.stereoPanning, default: true)
        audibleModifierKeys = store.bool(Key.audibleModifierKeys, default: true)
        ignoreKeyRepeat = store.bool(Key.ignoreKeyRepeat, default: true)
        playMouseClicks = store.bool(Key.playMouseClicks, default: true)
        playDingOnReturn = store.bool(Key.playDingOnReturn, default: false)
        sleepOnMicrophone = store.bool(Key.sleepOnMicrophone, default: true)
        sleepOnCamera = store.bool(Key.sleepOnCamera, default: true)
        sleepOnNowPlaying = store.bool(Key.sleepOnNowPlaying, default: false)
        sleepVolume = store.double(Key.sleepVolume, default: 0)
        switch store.string(forKey: Key.hotKey) {
        case nil: hotKey = .standard
        case "off": hotKey = nil
        case let stored?: hotKey = HotKeyCombo(storageValue: stored) ?? .standard
        }
        dimMenuBarIconWhenOff = store.bool(Key.dimMenuBarIconWhenOff, default: true)
        hasCompletedOnboarding = store.bool(Key.hasCompletedOnboarding, default: false)
        outputDeviceUID = store.string(forKey: Key.outputDeviceUID) ?? ""
        tonePitch = store.double(Key.tonePitch, default: 0)
        toneBrightness = store.double(Key.toneBrightness, default: 0)
        notifyOnSleepChange = store.bool(Key.notifyOnSleepChange, default: false)
    }
}

private extension UserDefaults {
    func bool(_ key: String, default fallback: Bool) -> Bool {
        object(forKey: key) as? Bool ?? fallback
    }

    func double(_ key: String, default fallback: Double) -> Double {
        object(forKey: key) as? Double ?? fallback
    }
}
