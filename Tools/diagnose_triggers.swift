// Prints what Kliq's sleep triggers see right now: processes running audio
// input or output, and cameras that are running somewhere.
//
//   swift Tools/diagnose_triggers.swift
import CoreAudio
import CoreMediaIO
import Foundation

func audioAddress(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
}

func processObjects() -> [AudioObjectID] {
    var address = audioAddress(kAudioHardwarePropertyProcessObjectList)
    let system = AudioObjectID(kAudioObjectSystemObject)
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
    var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
    guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids) == noErr else { return [] }
    return ids
}

func u32(_ selector: AudioObjectPropertySelector, _ object: AudioObjectID) -> UInt32 {
    var address = audioAddress(selector)
    var value: UInt32 = 0
    var size = UInt32(MemoryLayout<UInt32>.size)
    guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr else { return 0 }
    return value
}

func pid(_ object: AudioObjectID) -> pid_t {
    var address = audioAddress(kAudioProcessPropertyPID)
    var value: pid_t = 0
    var size = UInt32(MemoryLayout<pid_t>.size)
    guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr else { return -1 }
    return value
}

func bundleID(_ object: AudioObjectID) -> String {
    var address = audioAddress(kAudioProcessPropertyBundleID)
    var value: CFString = "" as CFString
    var size = UInt32(MemoryLayout<CFString>.size)
    guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr else { return "?" }
    return value as String
}

print("Audio processes (only those running input or output):")
var inputRunning = false
for object in processObjects() {
    let input = u32(kAudioProcessPropertyIsRunningInput, object)
    let output = u32(kAudioProcessPropertyIsRunningOutput, object)
    if input == 1 || output == 1 {
        let p = pid(object)
        let name = ProcessInfo.processInfo.processIdentifier == p ? "(this script)" : bundleID(object)
        print("  pid \(p)  \(name)  input=\(input) output=\(output)")
        if input == 1 && p != ProcessInfo.processInfo.processIdentifier { inputRunning = true }
    }
}
print("=> microphone trigger would be: \(inputRunning ? "ACTIVE (Kliq sleeps)" : "inactive")")

func cmioAddress(_ selector: Int) -> CMIOObjectPropertyAddress {
    CMIOObjectPropertyAddress(mSelector: CMIOObjectPropertySelector(selector),
                              mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
                              mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
}

let cmioSystem = CMIOObjectID(kCMIOObjectSystemObject)
var devicesAddress = cmioAddress(kCMIOHardwarePropertyDevices)
var devicesSize: UInt32 = 0
var cameraRunning = false
print("Cameras:")
if CMIOObjectGetPropertyDataSize(cmioSystem, &devicesAddress, 0, nil, &devicesSize) == noErr, devicesSize > 0 {
    var ids = [CMIOObjectID](repeating: 0, count: Int(devicesSize) / MemoryLayout<CMIOObjectID>.size)
    var used: UInt32 = 0
    if CMIOObjectGetPropertyData(cmioSystem, &devicesAddress, 0, nil, devicesSize, &used, &ids) == noErr {
        for device in ids {
            var runningAddress = cmioAddress(kCMIODevicePropertyDeviceIsRunningSomewhere)
            var running: UInt32 = 0
            var runningUsed: UInt32 = 0
            CMIOObjectGetPropertyData(device, &runningAddress, 0, nil, UInt32(MemoryLayout<UInt32>.size), &runningUsed, &running)
            var uidAddress = cmioAddress(kCMIODevicePropertyDeviceUID)
            var uid: CFString = "" as CFString
            var uidUsed: UInt32 = 0
            CMIOObjectGetPropertyData(device, &uidAddress, 0, nil, UInt32(MemoryLayout<CFString>.size), &uidUsed, &uid)
            print("  \(uid as String)  running=\(running)")
            if running != 0 { cameraRunning = true }
        }
    }
}
print("=> camera trigger would be: \(cameraRunning ? "ACTIVE (Kliq sleeps)" : "inactive")")
