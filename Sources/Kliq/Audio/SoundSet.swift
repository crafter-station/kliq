import Foundation

/// A folder of `<code>-down.<ext>` / `<code>-up.<ext>` samples, one pair per key,
/// where `<code>` is a PC scan code (see `KeyMapper`).
struct SoundSet: Identifiable, Hashable {
    let name: String
    let url: URL
    /// Scan codes that have a `-down` sample, sorted.
    let codes: [Int]
    let isBuiltIn: Bool

    var id: String { name }
    var keyCount: Int { codes.count }

    static let audioExtensions = ["wav", "caf", "aiff", "aif", "m4a", "mp3"]

    func sampleURL(code: Int, down: Bool) -> URL? {
        let stem = "\(code)-\(down ? "down" : "up")"
        for ext in Self.audioExtensions {
            let candidate = url.appendingPathComponent("\(stem).\(ext)")
            if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
        }
        return nil
    }

    /// Builds a set from a directory, or nil if it holds no `<code>-down` samples.
    static func load(directory: URL, isBuiltIn: Bool) -> SoundSet? {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { return nil }
        var codes = Set<Int>()
        for file in files where audioExtensions.contains(file.pathExtension.lowercased()) {
            let stem = file.deletingPathExtension().lastPathComponent
            guard stem.hasSuffix("-down"), let code = Int(stem.dropLast(5)), code > 0 else { continue }
            codes.insert(code)
        }
        guard !codes.isEmpty else { return nil }
        return SoundSet(name: directory.lastPathComponent, url: directory, codes: codes.sorted(), isBuiltIn: isBuiltIn)
    }
}

/// The definitive sound library shipped inside Kliq.
enum SoundLibrary {
    /// This order is also the order shown in Settings and the menu bar.
    static let bundledSetNames = ["KAT", "Cherry", "MT3", "XDA", "OEM", "SA", "DSA"]

    static var bundledDirectory: URL? {
        return Bundle.main.resourceURL?.appendingPathComponent("Sounds", isDirectory: true)
    }

    static func discover() -> [SoundSet] {
        guard let root = bundledDirectory else { return [] }
        return bundledSetNames.compactMap { name in
            SoundSet.load(directory: root.appendingPathComponent(name, isDirectory: true), isBuiltIn: true)
        }
    }

    /// Top-level effect sample such as `ding` or `left-down`.
    static func effectURL(_ name: String) -> URL? {
        guard let root = bundledDirectory else { return nil }
        for ext in SoundSet.audioExtensions {
            let candidate = root.appendingPathComponent("\(name).\(ext)")
            if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
        }
        return nil
    }
}
