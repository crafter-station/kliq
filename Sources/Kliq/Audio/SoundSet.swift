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

/// Finds sound sets in the app bundle and, when it exists, the user's Application Support
/// folder. Kliq never creates that folder; sets already in it load like the bundled ones.
enum SoundLibrary {
    static let userDirectory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("Kliq/Sounds", isDirectory: true)
    }()

    static var bundledDirectory: URL? {
        if let override = ProcessInfo.processInfo.environment["KLIQ_SOUNDS_DIR"] {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return Bundle.main.resourceURL?.appendingPathComponent("Sounds", isDirectory: true)
    }

    static func discover() -> [SoundSet] {
        var result: [SoundSet] = []
        var seen = Set<String>()
        let roots: [(URL?, Bool)] = [(bundledDirectory, true), (userDirectory, false)]
        for (root, builtIn) in roots {
            guard let root,
                  let entries = try? FileManager.default.contentsOfDirectory(
                      at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
            else { continue }
            let sorted = entries.sorted {
                $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
            }
            for url in sorted {
                guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true,
                      let set = SoundSet.load(directory: url, isBuiltIn: builtIn),
                      !seen.contains(set.name) else { continue }
                seen.insert(set.name)
                result.append(set)
            }
        }
        return result
    }

    /// Top-level effect sample such as `ding` or `left-down`, user folder first.
    static func effectURL(_ name: String) -> URL? {
        for root in [userDirectory, bundledDirectory].compactMap({ $0 }) {
            for ext in SoundSet.audioExtensions {
                let candidate = root.appendingPathComponent("\(name).\(ext)")
                if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
            }
        }
        return nil
    }
}
