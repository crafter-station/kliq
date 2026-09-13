import AppKit
import Carbon

/// A global shortcut: a virtual key code plus a Carbon modifier mask, the form
/// RegisterEventHotKey takes.
struct HotKeyCombo: Hashable {
    var keyCode: UInt32
    var modifiers: UInt32

    /// ⌃⌥K
    static let standard = HotKeyCombo(keyCode: UInt32(kVK_ANSI_K), modifiers: UInt32(controlKey | optionKey))

    init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// Builds a combo from a key press, or nil when it has no ⌃, ⌥ or ⌘: a global
    /// shortcut without one of those would swallow ordinary typing.
    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var mask: UInt32 = 0
        if flags.contains(.control) { mask |= UInt32(controlKey) }
        if flags.contains(.option) { mask |= UInt32(optionKey) }
        if flags.contains(.shift) { mask |= UInt32(shiftKey) }
        if flags.contains(.command) { mask |= UInt32(cmdKey) }
        guard mask & UInt32(controlKey | optionKey | cmdKey) != 0 else { return nil }
        self.init(keyCode: UInt32(event.keyCode), modifiers: mask)
    }

    /// Stored in UserDefaults as "keyCode:modifiers".
    var storageValue: String { "\(keyCode):\(modifiers)" }

    init?(storageValue: String) {
        let parts = storageValue.split(separator: ":").compactMap { UInt32($0) }
        guard parts.count == 2 else { return nil }
        self.init(keyCode: parts[0], modifiers: parts[1])
    }

    /// One label per keycap, modifiers first in the order macOS menus use: ⌃ ⌥ ⇧ ⌘.
    var keycaps: [String] {
        var caps: [String] = []
        if modifiers & UInt32(controlKey) != 0 { caps.append("⌃") }
        if modifiers & UInt32(optionKey) != 0 { caps.append("⌥") }
        if modifiers & UInt32(shiftKey) != 0 { caps.append("⇧") }
        if modifiers & UInt32(cmdKey) != 0 { caps.append("⌘") }
        caps.append(Self.keyName(keyCode))
        return caps
    }

    var label: String { keycaps.joined() }

    // MARK: Key names

    private static let specialKeys: [Int: String] = [
        kVK_Return: "↩", kVK_Tab: "⇥", kVK_Space: "Space", kVK_Delete: "⌫", kVK_ForwardDelete: "⌦",
        kVK_Escape: "⎋", kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
        kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
    ]

    /// The key's name on the user's current keyboard layout, so the label matches
    /// the printed keycap on AZERTY, QWERTZ and other layouts too.
    static func keyName(_ code: UInt32) -> String {
        if let special = specialKeys[Int(code)] { return special }
        return layoutCharacter(code)?.uppercased() ?? "#\(code)"
    }

    private static func layoutCharacter(_ code: UInt32) -> String? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let raw = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(raw).takeUnretainedValue() as Data
        var deadKeyState: UInt32 = 0
        var length = 0
        var chars = [UniChar](repeating: 0, count: 4)
        let status = data.withUnsafeBytes { buffer -> OSStatus in
            guard let layout = buffer.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return -1 }
            return UCKeyTranslate(layout, UInt16(code), UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                                  OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeyState, chars.count, &length, &chars)
        }
        guard status == noErr, length > 0 else { return nil }
        let string = String(utf16CodeUnits: chars, count: length).trimmingCharacters(in: .whitespacesAndNewlines)
        return string.isEmpty ? nil : string
    }
}
