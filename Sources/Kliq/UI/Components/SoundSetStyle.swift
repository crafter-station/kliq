/// How a sound set is named in the menu bar menu and Settings.
extension SoundSet {
    /// Bundled sets drop their "Synth " prefix: "Thock" reads better in a menu.
    var displayName: String {
        isBuiltIn && name.hasPrefix("Synth ") ? String(name.dropFirst("Synth ".count)) : name
    }

    /// Who designed the set, shown next to its name where sets are picked.
    var credit: String? {
        isBuiltIn && name.hasPrefix("Synth ") ? "by Cris" : nil
    }

    /// The name with its credit, such as "Thock · by Cris".
    var creditedName: String {
        credit.map { "\(displayName) · \($0)" } ?? displayName
    }
}
