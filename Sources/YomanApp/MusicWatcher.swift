import AppKit

/// Knows whether Apple Music or Spotify is playing, from the notifications both apps broadcast on every
/// play / pause / track change. Event-driven and needs no permission. Only the track name and artist are read.
final class MusicWatcher {
    struct Track: Equatable {
        var name: String?
        var artist: String?
    }

    /// (is anything playing, the track that just started or changed, if any)
    var onChange: ((Bool, Track?) -> Void)?

    private static let sources: [(notification: String, bundleID: String)] = [
        ("com.apple.Music.playerInfo", "com.apple.Music"),
        ("com.spotify.client.PlaybackStateChanged", "com.spotify.client"),
    ]

    private var playing: [String: Track] = [:]  // bundle id → current track while playing
    private var observers: [NSObjectProtocol] = []

    var isPlaying: Bool { !playing.isEmpty }

    func start() {
        guard observers.isEmpty else { return }
        let dnc = DistributedNotificationCenter.default()
        for src in Self.sources {
            observers.append(dnc.addObserver(forName: Notification.Name(src.notification), object: nil, queue: .main) {
                [weak self] n in self?.handle(n, from: src.bundleID)
            })
        }
        // A player that quits stops playing without always saying so.
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main
        ) { [weak self] n in
            guard let self, let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  let id = app.bundleIdentifier, self.playing[id] != nil else { return }
            self.playing[id] = nil
            self.onChange?(self.isPlaying, nil)
        })
    }

    func stop() {
        let dnc = DistributedNotificationCenter.default()
        observers.forEach { dnc.removeObserver($0); NSWorkspace.shared.notificationCenter.removeObserver($0) }
        observers.removeAll()
    }

    private func handle(_ n: Notification, from bundleID: String) {
        let info = n.userInfo ?? [:]
        let state = info["Player State"] as? String
        let track = Track(name: info["Name"] as? String, artist: info["Artist"] as? String)
        let before = playing[bundleID]
        if state == "Playing" {
            playing[bundleID] = track
            // Announce only a new track (or playback starting), not every repeated notification.
            onChange?(true, before == track ? nil : track)
        } else {
            playing[bundleID] = nil
            onChange?(isPlaying, nil)
        }
    }
}
