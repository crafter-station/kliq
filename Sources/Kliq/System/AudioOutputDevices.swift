import CoreAudio
import Foundation
import Observation
import os

/// Output devices the user can route Kliq to, kept current as devices come and go.
@Observable @MainActor
final class AudioOutputDevices {
    struct Device: Identifiable, Hashable {
        /// Core Audio device UID, stable across reboots and reconnects.
        let uid: String
        let name: String
        var id: String { uid }
    }

    /// Every device with output channels, sorted by name. Empty until `start()`.
    private(set) var devices: [Device] = []

    @ObservationIgnored private var listener: AudioObjectPropertyListenerBlock?
    @ObservationIgnored private let queue = DispatchQueue(label: "run.crafter.kliq.devices")
    @ObservationIgnored private let log = Logger(subsystem: "run.crafter.kliq", category: "audio")

    /// Lists the devices now and again whenever one is added or removed.
    func start() {
        guard listener == nil else { return }
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor in self?.refresh() }
        }
        var address = Self.propertyAddress(kAudioHardwarePropertyDevices)
        if AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, queue, block) == noErr {
            listener = block
        }
        refresh()
    }

    /// Reads the list off the main thread: the HAL can stall while a device connects.
    private func refresh() {
        queue.async { [weak self] in
            let list = Self.scan()
            Task { @MainActor in self?.publish(list) }
        }
    }

    private func publish(_ list: [Device]) {
        guard list != devices else { return }
        devices = list
        log.notice("Output devices: \(list.count) (\(list.map(\.name).joined(separator: ", ")))")
    }

    // MARK: Core Audio helpers

    /// Every visible device with output channels, sorted by name.
    nonisolated static func scan() -> [Device] {
        deviceIDs()
            .compactMap { id -> Device? in
                guard hasOutput(id), uint32(kAudioDevicePropertyIsHidden, of: id) != 1,
                      let uid = string(kAudioDevicePropertyDeviceUID, of: id),
                      let name = string(kAudioObjectPropertyName, of: id) else { return nil }
                return Device(uid: uid, name: name)
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// The current ID of the device with `uid`, or nil when it isn't connected.
    nonisolated static func deviceID(forUID uid: String) -> AudioDeviceID? {
        var address = propertyAddress(kAudioHardwarePropertyTranslateUIDToDevice)
        var qualifier = uid as CFString
        var device = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = withUnsafeMutablePointer(to: &qualifier) {
            AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address,
                                       UInt32(MemoryLayout<CFString>.size), $0, &size, &device)
        }
        if status == noErr { return device == kAudioObjectUnknown ? nil : device }
        // The translation failed outright; match the UID by hand instead.
        return deviceIDs().first { string(kAudioDevicePropertyDeviceUID, of: $0) == uid }
    }

    nonisolated static func defaultOutputDevice() -> AudioDeviceID? {
        var address = propertyAddress(kAudioHardwarePropertyDefaultOutputDevice)
        var device = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr,
              device != kAudioObjectUnknown else { return nil }
        return device
    }

    nonisolated static func name(of device: AudioDeviceID) -> String {
        string(kAudioObjectPropertyName, of: device) ?? "device \(device)"
    }

    nonisolated private static func deviceIDs() -> [AudioObjectID] {
        var address = propertyAddress(kAudioHardwarePropertyDevices)
        let system = AudioObjectID(kAudioObjectSystemObject)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids) == noErr else { return [] }
        return Array(ids.prefix(Int(size) / MemoryLayout<AudioObjectID>.size))
    }

    /// True when the device has at least one output stream with channels.
    nonisolated private static func hasOutput(_ device: AudioObjectID) -> Bool {
        var address = propertyAddress(kAudioDevicePropertyStreamConfiguration, scope: kAudioObjectPropertyScopeOutput)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr, size > 0 else { return false }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, raw) == noErr else { return false }
        let buffers = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
        return buffers.contains { $0.mNumberChannels > 0 }
    }

    nonisolated private static func string(_ selector: AudioObjectPropertySelector, of object: AudioObjectID) -> String? {
        var address = propertyAddress(selector)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr, let value else { return nil }
        return value.takeRetainedValue() as String
    }

    nonisolated private static func uint32(_ selector: AudioObjectPropertySelector, of object: AudioObjectID) -> UInt32? {
        var address = propertyAddress(selector)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }

    nonisolated private static func propertyAddress(
        _ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }
}
