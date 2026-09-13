import CoreMediaIO
import Foundation

/// Reports whether any camera is in use, via CoreMediaIO's "running somewhere" flag.
final class CameraMonitor {
    var onChange: (@MainActor (Bool) -> Void)?
    private(set) var isActive = false

    private let queue = DispatchQueue(label: "run.crafter.kliq.camera")
    private var running = false
    private var timer: DispatchSourceTimer?
    private var devicesListener: CMIOObjectPropertyListenerBlock?
    private var deviceListeners: [CMIOObjectID: CMIOObjectPropertyListenerBlock] = [:]

    private static let systemObject = CMIOObjectID(kCMIOObjectSystemObject)
    private var devicesAddress = CameraMonitor.address(kCMIOHardwarePropertyDevices)
    private var runningAddress = CameraMonitor.address(kCMIODevicePropertyDeviceIsRunningSomewhere)

    func start() {
        queue.async { [self] in
            guard !running else { return }
            running = true
            let block: CMIOObjectPropertyListenerBlock = { [weak self] _, _ in
                self?.refreshDeviceListeners()
                self?.evaluate()
            }
            devicesListener = block
            CMIOObjectAddPropertyListenerBlock(Self.systemObject, &devicesAddress, queue, block)
            refreshDeviceListeners()
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
            if let devicesListener {
                CMIOObjectRemovePropertyListenerBlock(Self.systemObject, &devicesAddress, queue, devicesListener)
            }
            devicesListener = nil
            for (id, block) in deviceListeners {
                CMIOObjectRemovePropertyListenerBlock(id, &runningAddress, queue, block)
            }
            deviceListeners.removeAll()
            update(false)
        }
    }

    private func refreshDeviceListeners() {
        let current = Set(Self.devices())
        for (id, block) in deviceListeners where !current.contains(id) {
            CMIOObjectRemovePropertyListenerBlock(id, &runningAddress, queue, block)
            deviceListeners[id] = nil
        }
        for id in current where deviceListeners[id] == nil {
            let block: CMIOObjectPropertyListenerBlock = { [weak self] _, _ in self?.evaluate() }
            if CMIOObjectAddPropertyListenerBlock(id, &runningAddress, queue, block) == noErr {
                deviceListeners[id] = block
            }
        }
    }

    private func evaluate() {
        update(Self.devices().contains { Self.isRunningSomewhere($0) })
    }

    private func update(_ value: Bool) {
        guard value != isActive else { return }
        isActive = value
        if let onChange { Task { @MainActor in onChange(value) } }
    }

    // MARK: CoreMediaIO helpers

    private static func address(_ selector: Int) -> CMIOObjectPropertyAddress {
        CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(selector),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
    }

    static func devices() -> [CMIOObjectID] {
        var address = address(kCMIOHardwarePropertyDevices)
        var size: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(systemObject, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [CMIOObjectID](repeating: 0, count: Int(size) / MemoryLayout<CMIOObjectID>.size)
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(systemObject, &address, 0, nil, size, &used, &ids) == noErr else { return [] }
        return ids
    }

    static func isRunningSomewhere(_ device: CMIOObjectID) -> Bool {
        var address = address(kCMIODevicePropertyDeviceIsRunningSomewhere)
        var value: UInt32 = 0
        var used: UInt32 = 0
        let size = UInt32(MemoryLayout<UInt32>.size)
        guard CMIOObjectGetPropertyData(device, &address, 0, nil, size, &used, &value) == noErr else { return false }
        return value != 0
    }
}
