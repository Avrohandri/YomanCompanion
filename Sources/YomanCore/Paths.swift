import Foundation

/// Fixed locations shared by the app and the bridge.
public enum YomanPaths {
    public static var home: URL { FileManager.default.homeDirectoryForCurrentUser }

    public static var supportDir: URL {
        home.appendingPathComponent("Library/Application Support/Yoman", isDirectory: true)
    }

    /// Unix socket the app listens on. Must stay under 104 bytes (sun_path limit).
    public static var socket: URL { supportDir.appendingPathComponent("yoman.sock") }

    public static var logDir: URL { home.appendingPathComponent("Library/Logs/Yoman", isDirectory: true) }

    public static var bridgeLog: URL { logDir.appendingPathComponent("bridge.log") }

    public static var claudeSettings: URL { home.appendingPathComponent(".claude/settings.json") }
}
