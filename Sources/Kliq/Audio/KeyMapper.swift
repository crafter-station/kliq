import CoreGraphics

/// Maps macOS virtual key codes to the PC scan codes that name sample files.
///
/// Sound sets name their files by PC scan code (set 1): 2...11 is the number
/// row, 16...25 qwertyuiop,
/// 30...38 asdfghjkl, 44...50 zxcvbnm, 14 backspace, 28 return, 57 space,
/// 42 / 54 the shifts, 58 caps lock, 56 / 3640 option, 3675 / 3676 command,
/// and 57416 / 57419 / 57421 / 57424 the up / left / right / down arrows.
enum KeyMapper {
    static let capsLockKeyCode: Int64 = 57
    static let backspace = 14
    static let returnKey = 28
    static let space = 57

    /// Physical layout by scan code, one array per row. Used for stereo panning
    /// and by the sound generator.
    static let rows: [[Int]] = [
        [1, 59, 60, 61, 62, 63, 64, 65, 66, 67, 68, 87, 88],                 // esc F1...F12
        [41, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14],                    // ` 1...0 - = backspace
        [15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 43],            // tab q...p [ ] \
        [58, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 28],                // caps a...l ; ' return
        [42, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54],                    // shift z...m , . / shift
        [29, 56, 3675, 57, 3676, 3640, 57419, 57416, 57424, 57421],          // ctrl opt cmd space cmd opt arrows
    ]

    /// Extra codes that are not on the MacBook layout but that keys can produce.
    static let extraCodes: [Int] = [3613, 3612, 3637, 3655, 3657, 3663, 3665, 3666, 3667,
                                    55, 69, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 91, 92, 93]

    private static let scanCodeByKeyCode: [Int64: Int] = [
        0: 30, 1: 31, 2: 32, 3: 33, 4: 35, 5: 34, 6: 44, 7: 45, 8: 46, 9: 47, 10: 41, 11: 48,
        12: 16, 13: 17, 14: 18, 15: 19, 16: 21, 17: 20, 18: 2, 19: 3, 20: 4, 21: 5, 22: 7, 23: 6,
        24: 13, 25: 10, 26: 8, 27: 12, 28: 9, 29: 11, 30: 27, 31: 24, 32: 22, 33: 26, 34: 23, 35: 25,
        36: 28, 37: 38, 38: 36, 39: 40, 40: 37, 41: 39, 42: 43, 43: 51, 44: 53, 45: 49, 46: 50, 47: 52,
        48: 15, 49: 57, 50: 41, 51: 14, 53: 1,
        54: 3676, 55: 3675, 56: 42, 57: 58, 58: 56, 59: 29, 60: 54, 61: 3640, 62: 3613, 63: 3613,
        65: 83, 67: 55, 69: 78, 71: 69, 75: 3637, 76: 3612, 78: 74, 81: 13,
        82: 82, 83: 79, 84: 80, 85: 81, 86: 75, 87: 76, 88: 77, 89: 71, 91: 72, 92: 73,
        96: 63, 97: 64, 98: 65, 99: 61, 100: 66, 101: 67, 103: 87, 105: 91, 107: 92, 109: 68,
        111: 88, 113: 93, 114: 3666, 115: 3655, 116: 3657, 117: 3667, 118: 62, 119: 3663,
        120: 60, 121: 3665, 122: 59, 123: 57419, 124: 57421, 125: 57424, 126: 57416,
    ]

    /// Preferred substitutes when a set has no sample for a code.
    private static let fallbacks: [Int: [Int]] = [
        1: [41, 2], 59: [2], 60: [3], 61: [4], 62: [5], 63: [6], 64: [7], 65: [8], 66: [9],
        67: [10], 68: [11], 87: [12], 88: [13], 91: [12], 92: [13], 93: [14],
        3613: [29, 56, 3640], 29: [56, 3675], 56: [29, 3640, 3675], 3640: [56, 29],
        3675: [3676, 56], 3676: [3675, 56], 54: [42], 42: [54],
        3612: [28], 3637: [53], 55: [9], 78: [13], 74: [12], 69: [11], 83: [52],
        82: [11], 79: [2], 80: [3], 81: [4], 75: [5], 76: [6], 77: [7], 71: [8], 72: [9], 73: [10],
        3666: [14], 3667: [14], 3655: [57419], 3663: [57421], 3657: [57416], 3665: [57424],
        57419: [57421, 53], 57421: [57419, 53], 57416: [57424, 53], 57424: [57416, 53],
    ]

    private static let panByScanCode: [Int: Float] = {
        var table: [Int: Float] = [:]
        for row in rows {
            let width = Float(max(1, row.count - 1))
            for (column, code) in row.enumerated() {
                table[code] = (Float(column) / width * 2 - 1) * 0.35
            }
        }
        for code in [3613, 3612, 3637, 55, 69, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83] { table[code] = 0.4 }
        for code in [3655, 3657, 3663, 3665, 3666, 3667, 91, 92, 93] { table[code] = 0.35 }
        return table
    }()

    /// Every scan code the mapper can emit.
    static var allScanCodes: [Int] {
        Array(Set(scanCodeByKeyCode.values)).sorted()
    }

    static func scanCode(for keyCode: Int64) -> Int {
        scanCodeByKeyCode[keyCode] ?? (30 + Int(keyCode % 9))
    }

    static func pan(forScanCode code: Int) -> Float {
        panByScanCode[code] ?? 0
    }

    static func isReturn(_ keyCode: Int64) -> Bool {
        keyCode == 36 || keyCode == 76
    }

    /// Picks the sample code to play for `code` given the codes a set provides.
    /// Rows are contiguous in scan-code space, so the nearest code is a neighbour key.
    static func resolve(_ code: Int, available: Set<Int>) -> Int? {
        if available.contains(code) { return code }
        for candidate in fallbacks[code] ?? [] where available.contains(candidate) { return candidate }
        let main = available.filter { $0 < 100 }
        if let nearest = main.min(by: { abs($0 - code) < abs($1 - code) }) { return nearest }
        return available.min()
    }

    /// For a `flagsChanged` event, decides whether the modifier went down or up.
    static func isModifierDown(keyCode: Int64, flags: CGEventFlags) -> Bool {
        switch keyCode {
        case 54, 55: return flags.contains(.maskCommand)
        case 56, 60: return flags.contains(.maskShift)
        case 58, 61: return flags.contains(.maskAlternate)
        case 59, 62: return flags.contains(.maskControl)
        case 63: return flags.contains(.maskSecondaryFn)
        case capsLockKeyCode: return true   // caps lock toggles; treat every event as a press
        default: return false
        }
    }
}
