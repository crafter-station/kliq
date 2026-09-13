/// How a sound set is named in the menu bar menu and Settings.
extension SoundSet {
    /// Bundled sets drop their "Synth " prefix: "Butter" reads better in a menu.
    var displayName: String {
        isBuiltIn && name.hasPrefix("Synth ") ? String(name.dropFirst("Synth ".count)) : name
    }
}
