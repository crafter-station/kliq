import AppKit
import Foundation

/// Reports whether Music or Spotify is playing, from the playback-state
/// notifications both apps broadcast. Nothing is sent to the players, so no
/// permission is needed and a player that just quit is never relaunched.
///
/// Neither app announces its state on request, so right after start() the state
/// is unknown (treated as not playing) until a player next plays, pauses or stops.
final class NowPlayingMonitor: NSObject {
    var onChange: (@MainActor (Bool) -> Void)?
    private(set) var isActive = false

    private let queue = DispatchQueue(label: "run.crafter.kliq.nowplaying", qos: .utility)
    private var running = false
    private var playingIDs: Set<String> = []

    /// Each player's bundle ID and the notification it posts on every state change.
    private static let players: [(bundleID: String, notification: Notification.Name)] = [
        ("com.apple.Music", Notification.Name("com.apple.Music.playerInfo")),
        ("com.spotify.client", Notification.Name("com.spotify.client.PlaybackStateChanged")),
    ]

    func start() {
        queue.async { [self] in
            guard !running else { return }
            running = true
            // Deliver immediately: a menu bar app is almost never the active app, and
            // by default distributed notifications are held until it becomes active.
            for player in Self.players {
                DistributedNotificationCenter.default().addObserver(
                    self, selector: #selector(playerStateChanged(_:)), name: player.notification,
                    object: nil, suspensionBehavior: .deliverImmediately)
            }
            NSWorkspace.shared.notificationCenter.addObserver(
                self, selector: #selector(applicationTerminated(_:)),
                name: NSWorkspace.didTerminateApplicationNotification, object: nil)
        }
    }

    func stop() {
        queue.async { [self] in
            guard running else { return }
            running = false
            DistributedNotificationCenter.default().removeObserver(self)
            NSWorkspace.shared.notificationCenter.removeObserver(self)
            playingIDs.removeAll()
            update(false)
        }
    }

    @objc private func playerStateChanged(_ note: Notification) {
        guard let player = Self.players.first(where: { $0.notification == note.name }),
              let state = note.userInfo?["Player State"] as? String else { return }
        let bundleID = player.bundleID
        queue.async { [weak self] in self?.set(bundleID, playing: state == "Playing") }
    }

    /// A player that quits while playing does not always post a final state.
    @objc private func applicationTerminated(_ note: Notification) {
        let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        guard let bundleID = app?.bundleIdentifier,
              Self.players.contains(where: { $0.bundleID == bundleID }) else { return }
        queue.async { [weak self] in self?.set(bundleID, playing: false) }
    }

    private func set(_ bundleID: String, playing: Bool) {
        guard running else { return }
        if playing { playingIDs.insert(bundleID) } else { playingIDs.remove(bundleID) }
        update(!playingIDs.isEmpty)
    }

    private func update(_ value: Bool) {
        guard value != isActive else { return }
        isActive = value
        if let onChange { Task { @MainActor in onChange(value) } }
    }
}
