import AudioToolbox
import AVFoundation
import CoreAudio
import Foundation
import os

/// Low-latency polyphonic sample player built on AVAudioEngine.
///
/// Thread-safe: `handle(_:)` is called from the event-tap thread, everything
/// else from the main thread. Sample banks and config are swapped under a lock,
/// and every engine and node call runs on one serial queue.
///
/// The engine pauses after a short idle period so macOS can power down the audio
/// device and let the Mac sleep; the next sound starts it again.
final class SoundEngine {
    struct Config {
        var enabled = true
        var muted = false
        var effectsGain: Float = 1
        var pitchVariation = true
        var stereoPanning = true
        var audibleModifiers = true
        var ignoreKeyRepeat = true
        var mouseClicks = true
        var dingOnReturn = false
        /// -1...1, see `Settings.tonePitch`.
        var pitchShift: Float = 0
        /// -1...1, see `Settings.toneBrightness`.
        var brightness: Float = 0

        /// Playback rate for `pitchShift`: up to three semitones down or up.
        var toneRate: Float { exp2(max(-1, min(1, pitchShift)) * 3 / 12) }
    }

    enum Played {
        case key(code: Int, down: Bool)
        case modifier(down: Bool)
        case ding
        case click(down: Bool)
    }

    /// Players connect straight to the mixer. Pitch variation and tone are baked into
    /// the scheduled buffer (see `repitched` and `tilted`) instead of a varispeed or EQ
    /// unit per voice, which would process silence continuously and cost CPU while idle.
    private struct Voice {
        let player: AVAudioPlayerNode
    }

    /// Decoded samples for one set, keyed by scan code, plus the shared effects.
    private struct Bank {
        var name = ""
        var down: [Int: AVAudioPCMBuffer] = [:]
        var up: [Int: AVAudioPCMBuffer] = [:]
        /// Scan code the mapper can emit -> code that actually has a sample.
        var resolved: [Int: Int] = [:]
        var effects: [String: AVAudioPCMBuffer] = [:]

        var isEmpty: Bool { down.isEmpty }

        func buffer(forScanCode code: Int, down isDown: Bool) -> AVAudioPCMBuffer? {
            let key = resolved[code] ?? code
            return isDown ? down[key] : up[key]
        }

        func effect(_ names: [String]) -> AVAudioPCMBuffer? {
            for name in names { if let buffer = effects[name] { return buffer } }
            return nil
        }
    }

    private struct PreviewStep {
        let delay: Double
        let buffer: AVAudioPCMBuffer
    }

    private static let previewPattern: [(delay: Double, code: Int, down: Bool)] = [
        (0.00, 33, true), (0.08, 33, false),
        (0.18, 36, true), (0.26, 36, false),
        (0.40, KeyMapper.space, true), (0.50, KeyMapper.space, false),
    ]

    private static let effectNames = ["ding", "click", "left-down", "left-up", "right-down", "right-up"]

    var onPlayed: (@Sendable (Played) -> Void)?

    private let engine = AVAudioEngine()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2)!
    private var keyVoices: [Voice] = []
    private var effectVoices: [Voice] = []
    private var keyVoiceIndex = 0
    private var effectVoiceIndex = 0
    private let lock = NSLock()
    private var bank = Bank()
    private var config = Config()
    private var loadGeneration = 0
    private var previewGeneration = 0
    private var previewCache: [String: [PreviewStep]] = [:]
    private var configObserver: NSObjectProtocol?
    private let log = Logger(subsystem: "run.crafter.kliq", category: "audio")

    /// Serializes engine and node calls, which AVAudioEngine does not make thread-safe.
    private let audioQueue = DispatchQueue(label: "run.crafter.kliq.audio", qos: .userInteractive)
    private var pauseWork: DispatchWorkItem?
    private static let idlePause: TimeInterval = 20

    // Output routing, only touched on `audioQueue`.
    private enum Route: Equatable { case system, device(AudioDeviceID) }
    /// UID of the device chosen in Settings, or nil to follow the system output.
    private var outputUID: String?
    /// True once Kliq has pointed the output unit at a device itself. Until then
    /// AVAudioEngine follows the system output on its own.
    private var routedManually = false
    private var missingOutputUID: String?
    private var route: Route?
    private var defaultOutputListener: AudioObjectPropertyListenerBlock?

    init(voices: Int = 24) {
        for _ in 0..<voices { keyVoices.append(makeVoice()) }
        for _ in 0..<4 { effectVoices.append(makeVoice()) }
        engine.prepare()
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil
        ) { [weak self] _ in
            // The engine has stopped itself; the next sound starts it on the new device.
            self?.log.info("Audio configuration changed")
            self?.audioQueue.async { self?.reapplyOutputRouting() }
        }
    }

    deinit {
        if let configObserver { NotificationCenter.default.removeObserver(configObserver) }
        if let defaultOutputListener {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain)
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, audioQueue, defaultOutputListener)
        }
    }

    // MARK: Control

    var masterVolume: Float {
        get { engine.mainMixerNode.outputVolume }
        set { engine.mainMixerNode.outputVolume = max(0, min(1, newValue)) }
    }

    var loadedSetName: String { lock.withLock { bank.name } }

    /// Returns false if the output device could not be started. Not fatal: every
    /// sound tries again.
    @discardableResult
    func start() -> Bool {
        audioQueue.sync { ensureRunning() }
    }

    func stop() {
        audioQueue.sync {
            pauseWork?.cancel()
            engine.stop()
        }
    }

    func update(config: Config) {
        lock.withLock { self.config = config }
    }

    /// Routes sound to the device with `uid`, or follows the system output when it is
    /// nil or empty. A missing device falls back to the system output until it returns;
    /// call again when the device list changes.
    func setOutputDevice(uid: String?) {
        audioQueue.async { [self] in
            outputUID = uid?.isEmpty == false ? uid : nil
            applyOutputRouting()
        }
    }

    /// Loads a set plus the shared effects off the main thread and reports how many
    /// key samples were decoded. Unreadable files are skipped rather than failing the
    /// set, and only the most recent request is applied if loads finish out of order.
    func load(set: SoundSet?, completion: @escaping @MainActor (Int) -> Void) {
        let target = format
        let generation = lock.withLock { () -> Int in
            loadGeneration += 1
            return loadGeneration
        }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            var loaded = Bank()
            var skipped = 0
            func decode(_ url: URL?) -> AVAudioPCMBuffer? {
                guard let url else { return nil }
                if let buffer = try? Self.loadBuffer(url, format: target) { return buffer }
                skipped += 1
                return nil
            }
            if let set {
                loaded.name = set.name
                for code in set.codes {
                    loaded.down[code] = decode(set.sampleURL(code: code, down: true))
                    loaded.up[code] = decode(set.sampleURL(code: code, down: false))
                }
                let available = Set(loaded.down.keys)
                for code in KeyMapper.allScanCodes {
                    if let resolved = KeyMapper.resolve(code, available: available) { loaded.resolved[code] = resolved }
                }
            }
            for name in Self.effectNames {
                loaded.effects[name] = decode(SoundLibrary.effectURL(name))
            }
            if skipped > 0 {
                self.log.error("Skipped \(skipped) unreadable files while loading \(loaded.name, privacy: .public)")
            }
            let applied = self.lock.withLock { () -> Bool in
                guard generation == self.loadGeneration else { return false }
                self.bank = loaded
                return true
            }
            guard applied else { return }
            let count = loaded.down.count
            Task { @MainActor in completion(count) }
        }
    }

    /// Plays a short "click kliq" using the selected set and the current tone.
    func preview() {
        let (generation, snapshot) = lock.withLock { () -> (Int, Bank) in
            previewGeneration += 1
            return (previewGeneration, bank)
        }
        guard !snapshot.isEmpty else { return }
        playPreview(Self.previewSteps(from: snapshot), generation: generation)
    }

    /// Previews a set without selecting it or replacing the active playback bank.
    /// The six small samples are cached after their first hover.
    func preview(set: SoundSet) {
        let (generation, snapshot, cached) = lock.withLock { () -> (Int, Bank, [PreviewStep]?) in
            previewGeneration += 1
            return (previewGeneration, bank, previewCache[set.name])
        }
        if snapshot.name == set.name {
            playPreview(Self.previewSteps(from: snapshot), generation: generation)
            return
        }
        if let cached {
            playPreview(cached, generation: generation)
            return
        }

        let target = format
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let available = Set(set.codes)
            let steps = Self.previewPattern.compactMap { item -> PreviewStep? in
                guard let resolved = KeyMapper.resolve(item.code, available: available),
                      let url = set.sampleURL(code: resolved, down: item.down)
                else { return nil }
                do {
                    guard let buffer = try Self.loadBuffer(url, format: target) else { return nil }
                    return PreviewStep(delay: item.delay, buffer: buffer)
                } catch {
                    return nil
                }
            }
            guard !steps.isEmpty else { return }
            self.lock.withLock { self.previewCache[set.name] = steps }
            self.playPreview(steps, generation: generation)
        }
    }

    /// Stops the remainder of a hover preview when the pointer moves away.
    func cancelPreview() {
        lock.withLock { previewGeneration += 1 }
    }

    private static func previewSteps(from bank: Bank) -> [PreviewStep] {
        previewPattern.compactMap { item in
            guard let buffer = bank.buffer(forScanCode: item.code, down: item.down) else { return nil }
            return PreviewStep(delay: item.delay, buffer: buffer)
        }
    }

    private func playPreview(_ steps: [PreviewStep], generation: Int) {
        for step in steps {
            DispatchQueue.global(qos: .userInteractive).asyncAfter(deadline: .now() + step.delay) { [weak self] in
                guard let self else { return }
                let cfg = self.lock.withLock { () -> Config? in
                    generation == self.previewGeneration ? self.config : nil
                }
                guard let cfg else { return }
                self.play(step.buffer, on: self.nextVoice(), gain: 1, pitch: cfg.toneRate,
                          pan: 0, brightness: cfg.brightness)
            }
        }
    }

    // MARK: Input handling (event-tap thread)

    func handle(_ event: InputMonitor.Event) {
        let (cfg, snapshot) = lock.withLock { (config, bank) }
        guard cfg.enabled, !cfg.muted else { return }

        switch event {
        case .keyDown(let keyCode, let isRepeat):
            if isRepeat && cfg.ignoreKeyRepeat { return }
            playKey(keyCode, down: true, cfg, snapshot)
            if cfg.dingOnReturn, KeyMapper.isReturn(keyCode), let ding = snapshot.effect(["ding"]) {
                playEffect(ding, gain: cfg.effectsGain, pitch: 1)
                onPlayed?(.ding)
            }

        case .keyUp(let keyCode):
            playKey(keyCode, down: false, cfg, snapshot)

        case .modifierDown(let keyCode):
            guard cfg.audibleModifiers else { return }
            playKey(keyCode, down: true, cfg, snapshot, report: .modifier(down: true))
            if keyCode == KeyMapper.capsLockKeyCode {
                DispatchQueue.global(qos: .userInteractive).asyncAfter(deadline: .now() + 0.07) { [weak self] in
                    self?.playKey(keyCode, down: false, cfg, snapshot, report: .modifier(down: false))
                }
            }

        case .modifierUp(let keyCode):
            guard cfg.audibleModifiers else { return }
            playKey(keyCode, down: false, cfg, snapshot, report: .modifier(down: false))

        case .mouseDown(let button):
            guard cfg.mouseClicks else { return }
            let names = button == 1 ? ["right-down", "left-down", "click"] : ["left-down", "click"]
            guard let buffer = snapshot.effect(names) else { return }
            playEffect(buffer, gain: cfg.effectsGain, pitch: 1)
            onPlayed?(.click(down: true))

        case .mouseUp(let button):
            guard cfg.mouseClicks else { return }
            let names = button == 1 ? ["right-up", "left-up"] : ["left-up"]
            if let buffer = snapshot.effect(names) {
                playEffect(buffer, gain: cfg.effectsGain, pitch: 1)
            } else if let click = snapshot.effect(["click"]) {
                playEffect(click, gain: cfg.effectsGain * 0.55, pitch: 1.12)
            } else {
                return
            }
            onPlayed?(.click(down: false))
        }
    }

    // MARK: Playback

    private func playKey(_ keyCode: Int64, down: Bool, _ cfg: Config, _ snapshot: Bank, report: Played? = nil) {
        let code = KeyMapper.scanCode(for: keyCode)
        guard let buffer = snapshot.buffer(forScanCode: code, down: down) else { return }
        let variation: Float = cfg.pitchVariation ? Float.random(in: 0.95...1.05) : 1
        let pan: Float = cfg.stereoPanning ? KeyMapper.pan(forScanCode: code) : 0
        play(buffer, on: nextVoice(), gain: 1, pitch: variation * cfg.toneRate, pan: pan, brightness: cfg.brightness)
        onPlayed?(report ?? .key(code: code, down: down))
    }

    private func playEffect(_ buffer: AVAudioPCMBuffer, gain: Float, pitch: Float) {
        play(buffer, on: nextEffectVoice(), gain: gain, pitch: pitch, pan: 0)
    }

    private func play(_ buffer: AVAudioPCMBuffer, on voice: Voice, gain: Float, pitch: Float, pan: Float, brightness: Float = 0) {
        let pitched = Self.repitched(buffer, rate: pitch)
        let toned = Self.tilted(pitched, by: brightness, inPlace: pitched !== buffer)
        audioQueue.async { [self] in
            guard ensureRunning() else { return }
            voice.player.pan = pan
            voice.player.volume = gain
            voice.player.scheduleBuffer(toned, at: nil, options: .interrupts)
            if !voice.player.isPlaying { voice.player.play() }
        }
    }

    /// Starts or resumes the engine when needed and pushes back the idle pause.
    /// Runs on `audioQueue`. Returns false if the output device can't be started.
    private func ensureRunning() -> Bool {
        if !engine.isRunning {
            let began = DispatchTime.now()
            do {
                try engine.start()
            } catch {
                // After a device change the output connection can be stale; rebuild it once.
                engine.connect(engine.mainMixerNode, to: engine.outputNode, format: nil)
                do { try engine.start() } catch {
                    log.error("Engine start failed: \(error.localizedDescription, privacy: .public)")
                    return false
                }
            }
            let ms = Double(DispatchTime.now().uptimeNanoseconds - began.uptimeNanoseconds) / 1_000_000
            log.debug("Engine started in \(ms, format: .fixed(precision: 1)) ms")
        }
        schedulePause()
        return true
    }

    private func schedulePause() {
        pauseWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.engine.isRunning else { return }
            self.engine.pause()
            self.log.debug("Engine paused after idle")
        }
        pauseWork = work
        audioQueue.asyncAfter(deadline: .now() + Self.idlePause, execute: work)
    }

    private func nextVoice() -> Voice {
        lock.withLock {
            let voice = keyVoices[keyVoiceIndex]
            keyVoiceIndex = (keyVoiceIndex + 1) % keyVoices.count
            return voice
        }
    }

    private func nextEffectVoice() -> Voice {
        lock.withLock {
            let voice = effectVoices[effectVoiceIndex]
            effectVoiceIndex = (effectVoiceIndex + 1) % effectVoices.count
            return voice
        }
    }

    private func makeVoice() -> Voice {
        let player = AVAudioPlayerNode()
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        return Voice(player: player)
    }

    /// Returns `buffer` played back at `rate` (above 1 is higher and shorter), by
    /// linear interpolation. Runs per keystroke on the event-tap thread: a few
    /// thousand frames take microseconds, and nothing runs between keystrokes.
    private static func repitched(_ buffer: AVAudioPCMBuffer, rate: Float) -> AVAudioPCMBuffer {
        guard rate != 1, rate > 0, let src = buffer.floatChannelData else { return buffer }
        let inFrames = Int(buffer.frameLength)
        let outFrames = Int(Float(inFrames - 1) / rate)
        guard outFrames > 1,
              let output = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: AVAudioFrameCount(outFrames)),
              let dst = output.floatChannelData else { return buffer }
        for channel in 0..<Int(buffer.format.channelCount) {
            let s = src[channel], d = dst[channel]
            for i in 0..<outFrames {
                let position = Float(i) * rate
                let index = Int(position)
                d[i] = s[index] + (s[index + 1] - s[index]) * (position - Float(index))
            }
        }
        output.frameLength = AVAudioFrameCount(outFrames)
        return output
    }

    /// Tilts `buffer` darker (`amount` below 0) or brighter (above 0) around a one-pole
    /// low-pass: darker blends toward it, brighter adds back what it removes. Writes into
    /// `buffer` when it is already a private copy. Like `repitched`, microseconds per key.
    private static func tilted(_ buffer: AVAudioPCMBuffer, by amount: Float, inPlace: Bool) -> AVAudioPCMBuffer {
        let amount = max(-1, min(1, amount))
        guard amount != 0, let src = buffer.floatChannelData,
              let output = inPlace ? buffer : AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameLength),
              let dst = output.floatChannelData else { return buffer }
        output.frameLength = buffer.frameLength
        let frames = Int(buffer.frameLength)
        let channels = Int(buffer.format.channelCount)
        // Bundled samples are mono copied to both channels: filter one and copy it.
        let mono = channels == 2 && memcmp(src[0], src[1], frames * MemoryLayout<Float>.size) == 0
        let filtered = mono ? 1 : channels
        let cutoff = amount < 0 ? 1_800.0 : 3_000.0
        let coefficient = Float(1 - exp(-2 * Double.pi * cutoff / buffer.format.sampleRate))
        let decay = 1 - coefficient
        var peak: Float = 0
        for channel in 0..<filtered {
            let s = src[channel], d = dst[channel]
            var low: Float = 0
            for i in 0..<frames {
                let x = s[i]
                // A single fused multiply-add carries the low-pass from sample to sample.
                low = (coefficient * x).addingProduct(low, decay)
                // amount -1 gives the low-pass alone; +1 gives x + (x - low).
                let y = x + amount * (x - low)
                d[i] = y
                peak = max(peak, abs(y))
            }
        }
        // Brightening can push transients past full scale; scale the whole sample back.
        if peak > 1 {
            let scale = 1 / peak
            for channel in 0..<filtered {
                let d = dst[channel]
                for i in 0..<frames { d[i] *= scale }
            }
        }
        if mono { dst[1].update(from: dst[0], count: frames) }
        return output
    }

    // MARK: Output routing (audioQueue)

    /// Points the output unit at the chosen device, or at the system output when none
    /// is chosen or it is missing. The engine is stopped while the device changes; the
    /// next sound starts it again.
    private func applyOutputRouting() {
        var chosen: AudioDeviceID?
        if let uid = outputUID {
            chosen = AudioOutputDevices.deviceID(forUID: uid)
            if chosen == nil, missingOutputUID != uid {
                log.notice("Output device \(uid, privacy: .private) is missing; using the system output until it returns")
            }
            missingOutputUID = chosen == nil ? uid : nil
        } else {
            missingOutputUID = nil
        }

        let target: AudioDeviceID
        if let chosen {
            target = chosen
        } else if routedManually, let fallback = AudioOutputDevices.defaultOutputDevice() {
            target = fallback
        } else {
            if route != .system, !routedManually {
                route = .system
                log.notice("Output follows the system output")
            }
            return
        }

        guard let unit = engine.outputNode.audioUnit else { return }
        if routedManually, Self.currentDevice(of: unit) == target { return }
        pauseWork?.cancel()
        engine.stop()
        var device = target
        let status = AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0,
                                          &device, UInt32(MemoryLayout<AudioDeviceID>.size))
        guard status == noErr else {
            log.error("Routing output to device \(target) failed: \(status)")
            return
        }
        routedManually = true
        observeDefaultOutput()
        route = chosen == nil ? .system : .device(target)
        let name = AudioOutputDevices.name(of: target)
        if chosen == nil {
            log.notice("Output follows the system output: device \(target) \(name, privacy: .private)")
        } else {
            log.notice("Output routed to device \(target) \(name, privacy: .private)")
        }
    }

    /// AVAudioEngine may reset the device after a configuration change; put it back.
    private func reapplyOutputRouting() {
        guard routedManually else { return }
        applyOutputRouting()
    }

    /// Once the unit has a device of its own it no longer follows the system output,
    /// so track the default output while no chosen device is in use.
    private func observeDefaultOutput() {
        guard defaultOutputListener == nil else { return }
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.applyOutputRouting() }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        if AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, audioQueue, block) == noErr {
            defaultOutputListener = block
        }
    }

    private static func currentDevice(of unit: AudioUnit) -> AudioDeviceID? {
        var device = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioUnitGetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0,
                                   &device, &size) == noErr else { return nil }
        return device
    }

    // MARK: Decoding

    /// Reads any AVAudioFile-readable sample and converts it to the engine format
    /// (float32, 48 kHz, stereo). Mono sources are duplicated to both channels.
    private static func loadBuffer(_ url: URL, format target: AVAudioFormat) throws -> AVAudioPCMBuffer? {
        let file = try AVAudioFile(forReading: url)
        let source = file.processingFormat
        let frames = AVAudioFrameCount(file.length)
        guard frames > 0, let input = AVAudioPCMBuffer(pcmFormat: source, frameCapacity: frames) else { return nil }
        try file.read(into: input)

        let resampled: AVAudioPCMBuffer
        if source.sampleRate == target.sampleRate, source.commonFormat == .pcmFormatFloat32, !source.isInterleaved {
            resampled = input
        } else {
            guard let mid = AVAudioFormat(standardFormatWithSampleRate: target.sampleRate, channels: source.channelCount),
                  let converter = AVAudioConverter(from: source, to: mid) else { return nil }
            let capacity = AVAudioFrameCount(Double(frames) * target.sampleRate / source.sampleRate) + 1024
            guard let output = AVAudioPCMBuffer(pcmFormat: mid, frameCapacity: capacity) else { return nil }
            var supplied = false
            var conversionError: NSError?
            let status = converter.convert(to: output, error: &conversionError) { _, outStatus in
                if supplied {
                    outStatus.pointee = .endOfStream
                    return nil
                }
                supplied = true
                outStatus.pointee = .haveData
                return input
            }
            if status == .error { throw conversionError ?? CocoaError(.fileReadCorruptFile) }
            resampled = output
        }

        if resampled.format.channelCount == target.channelCount { return resampled }
        guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: resampled.frameLength),
              let src = resampled.floatChannelData,
              let dst = output.floatChannelData else { return nil }
        let count = Int(resampled.frameLength)
        let sourceChannels = Int(resampled.format.channelCount)
        for channel in 0..<Int(target.channelCount) {
            dst[channel].update(from: src[min(channel, sourceChannels - 1)], count: count)
        }
        output.frameLength = resampled.frameLength
        return output
    }
}
