/// How a sound set is named throughout the app.
extension SoundSet {
    /// Legacy bundled sets drop their old "Synth " prefix.
    var displayName: String {
        isBuiltIn && name.hasPrefix("Synth ") ? String(name.dropFirst("Synth ".count)) : name
    }
}
