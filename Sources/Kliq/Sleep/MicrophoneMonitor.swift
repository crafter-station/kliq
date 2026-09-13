import CoreAudio
import Foundation

/// Reports whether any *other* process is capturing audio input.
///
/// Uses the CoreAudio process-object API (macOS 14.2+), which exposes per-process
/// input/output activity. That avoids the classic false positive where our own
/// playback marks a combined input/output device (AirPods, USB headsets) as busy.
final class MicrophoneMonitor {
    var onChange: (@MainActor (Bool) -> Void)?
    private(set) var isActive = false

    private let queue = DispatchQueue(label: "run.crafter.kliq.microphone")
    private var running = false
    private var timer: DispatchSourceTimer?
    private var systemListener: AudioObjectPropertyListenerBlock?
    private var processListeners: [AudioObjectID: AudioObjectPropertyListenerBlock] = [:]

    private var listAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyProcessObjectList,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)
    private var runningInputAddress = AudioObjectPropertyAddress(
        mSelector: kAudioProcessPropertyIsRunningInput,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)

    func start() {
        queue.async { [self] in
            guard !running else { return }
            running = true
            let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                self?.refreshProcessListeners()
                self?.evaluate()
            }
            systemListener = block
            AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &listAddress, queue, block)
            refreshProcessListeners()
            // Safety net only; the listeners report changes as they happen.
            let source = DispatchSource.makeTimerSource(queue: queue)
            source.schedule(deadline: .now() + 30, repeating: 30, leeway: .seconds(5))
            source.setEventHandler { [weak self] in self?.evaluate() }
            source.resume()
            timer = source
            evaluate()
        }
    }

    func stop() {
        queue.async { [self] in
            guard running else { return }
            running = false
            timer?.cancel()
            timer = nil
            if let systemListener {
                AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &listAddress, queue, systemListener)
            }
            systemListener = nil
            for (id, block) in processListeners {
                AudioObjectRemovePropertyListenerBlock(id, &runningInputAddress, queue, block)
            }
            processListeners.removeAll()
            update(false)
        }
    }

    private func refreshProcessListeners() {
        let current = Set(Self.processObjects())
        for (id, block) in processListeners where !current.contains(id) {
            AudioObjectRemovePropertyListenerBlock(id, &runningInputAddress, queue, block)
            processListeners[id] = nil
        }
        for id in current where processListeners[id] == nil {
            let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.evaluate() }
            if AudioObjectAddPropertyListenerBlock(id, &runningInputAddress, queue, block) == noErr {
                processListeners[id] = block
            }
        }
    }

    private func evaluate() {
        update(Self.isAnyOtherProcessRunningInput())
    }

    private func update(_ value: Bool) {
        guard value != isActive else { return }
        isActive = value
        if let onChange { Task { @MainActor in onChange(value) } }
    }

    // MARK: CoreAudio helpers

    static func isAnyOtherProcessRunningInput() -> Bool {
        let me = getpid()
        for object in processObjects() {
            if let pid = pid(of: object), pid == me { continue }
            if uint32Property(kAudioProcessPropertyIsRunningInput, of: object) == 1 { return true }
        }
        return false
    }

    static func processObjects() -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        let system = AudioObjectID(kAudioObjectSystemObject)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids
    }

    static func uint32Property(_ selector: AudioObjectPropertySelector, of object: AudioObjectID) -> UInt32? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }

    static func pid(of object: AudioObjectID) -> pid_t? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyPID, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var value: pid_t = 0
        var size = UInt32(MemoryLayout<pid_t>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }
}
