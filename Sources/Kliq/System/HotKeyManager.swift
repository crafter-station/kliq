import Carbon
import Foundation

/// Global hotkey via Carbon's RegisterEventHotKey (works without Accessibility permission).
final class HotKeyManager {
    typealias Combo = (keyCode: UInt32, modifiers: UInt32)

    var onPressed: (@MainActor () -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private var current: Combo?

    /// Registers `combo`, replacing any previous one. Returns false if macOS refused
    /// it, usually because another app already owns the combination; nil always succeeds.
    @discardableResult
    func configure(_ combo: Combo?) -> Bool {
        if let combo, let current, combo == current { return true }
        unregister()
        guard let combo else { return true }
        installHandlerIfNeeded()
        var ref: EventHotKeyRef?
        let id = EventHotKeyID(signature: fourCharCode("KLIQ"), id: 1)
        let status = RegisterEventHotKey(combo.keyCode, combo.modifiers, id, GetApplicationEventTarget(), 0, &ref)
        guard status == noErr else { return false }
        hotKeyRef = ref
        current = combo
        return true
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        hotKeyRef = nil
        current = nil
    }

    private func installHandlerIfNeeded() {
        guard handlerRef == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(
            GetApplicationEventTarget(),
            HotKeyManager.callback,
            1,
            &spec,
            Unmanaged.passUnretained(self).toOpaque(),
            &handlerRef)
    }

    private static let callback: EventHandlerUPP = { _, _, userData in
        guard let userData else { return OSStatus(eventNotHandledErr) }
        let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
        if let onPressed = manager.onPressed {
            Task { @MainActor in onPressed() }
        }
        return noErr
    }

    private func fourCharCode(_ string: String) -> OSType {
        string.utf8.reduce(0) { ($0 << 8) | OSType($1) }
    }
}
