import Foundation

/// Adds and removes Yoman's entries in Claude Code's `~/.claude/settings.json`.
///
/// Only hook entries whose command runs `yoman-bridge ... hook` are ever touched; everything else in
/// the file is kept. Every write first copies the old file to `settings.json.yoman-backup`, then
/// replaces the file atomically.
public enum HookInstaller {
    /// The hook events the companion listens to.
    public static let events = [
        "SessionStart", "SessionEnd", "UserPromptSubmit", "PreToolUse", "PostToolUse",
        "PermissionRequest", "Notification", "Stop", "SubagentStop",
    ]

    /// Seconds Claude waits for the bridge; it normally exits in a few milliseconds.
    static let timeout = 5

    public static func command(bridgePath: String) -> String {
        "\"\(bridgePath)\" hook"
    }

    static func isOurs(_ hook: [String: Any]) -> Bool {
        guard let cmd = hook["command"] as? String else { return false }
        return cmd.contains("yoman-bridge") && cmd.hasSuffix(" hook")
    }

    // MARK: Pure transforms (tested)

    public static func installing(into settings: [String: Any], bridgePath: String) -> [String: Any] {
        var root = removing(from: settings)
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        let entry: [String: Any] = [
            "hooks": [["type": "command", "command": command(bridgePath: bridgePath), "timeout": timeout]],
        ]
        for event in events {
            var groups = hooks[event] as? [[String: Any]] ?? []
            groups.append(entry)
            hooks[event] = groups
        }
        root["hooks"] = hooks
        return root
    }

    public static func removing(from settings: [String: Any]) -> [String: Any] {
        var root = settings
        guard var hooks = root["hooks"] as? [String: Any] else { return root }
        for (event, value) in hooks {
            guard let groups = value as? [[String: Any]] else { continue }
            let kept: [[String: Any]] = groups.compactMap { group in
                guard let list = group["hooks"] as? [[String: Any]] else { return group }
                let rest = list.filter { !isOurs($0) }
                if rest.count == list.count { return group }
                if rest.isEmpty { return nil }
                var g = group
                g["hooks"] = rest
                return g
            }
            hooks[event] = kept.isEmpty ? nil : kept
        }
        root["hooks"] = hooks.isEmpty ? nil : hooks
        return root
    }

    /// True when every event has Yoman's hook pointing at `bridgePath`.
    public static func isInstalled(in settings: [String: Any], bridgePath: String) -> Bool {
        let want = command(bridgePath: bridgePath)
        guard let hooks = settings["hooks"] as? [String: Any] else { return false }
        return events.allSatisfy { event in
            let groups = hooks[event] as? [[String: Any]] ?? []
            return groups.contains { ($0["hooks"] as? [[String: Any]] ?? []).contains { $0["command"] as? String == want } }
        }
    }

    // MARK: File I/O

    public enum InstallError: Error, CustomStringConvertible {
        case unreadable(String)
        public var description: String {
            switch self { case .unreadable(let why): return why }
        }
    }

    public static func readSettings(at url: URL = YomanPaths.claudeSettings) throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [:] }
        let data = try Data(contentsOf: url)
        if data.isEmpty { return [:] }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw InstallError.unreadable("\(url.path) is not a JSON object; left untouched")
        }
        return obj
    }

    /// Writes `settings` if it differs from what's on disk. Returns whether the file changed.
    @discardableResult
    public static func writeSettings(_ settings: [String: Any], at url: URL = YomanPaths.claudeSettings) throws -> Bool {
        let fm = FileManager.default
        let new = try JSONSerialization.data(
            withJSONObject: settings, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        var mode: Int = 0o600
        if fm.fileExists(atPath: url.path) {
            let old = try Data(contentsOf: url)
            if let a = try? JSONSerialization.jsonObject(with: old) as? NSDictionary,
               a.isEqual(to: settings) { return false }
            mode = (try? fm.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int) ?? mode
            let backup = url.appendingPathExtension("yoman-backup")
            try? fm.removeItem(at: backup)
            try old.write(to: backup)
        } else {
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        }
        let tmp = url.appendingPathExtension("yoman-tmp")
        try (new + Data("\n".utf8)).write(to: tmp)
        try fm.setAttributes([.posixPermissions: mode], ofItemAtPath: tmp.path)
        _ = try fm.replaceItemAt(url, withItemAt: tmp)
        return true
    }

    @discardableResult
    public static func install(bridgePath: String, at url: URL = YomanPaths.claudeSettings) throws -> Bool {
        try writeSettings(installing(into: try readSettings(at: url), bridgePath: bridgePath), at: url)
    }

    @discardableResult
    public static func remove(at url: URL = YomanPaths.claudeSettings) throws -> Bool {
        try writeSettings(removing(from: try readSettings(at: url)), at: url)
    }

    public static func status(bridgePath: String, at url: URL = YomanPaths.claudeSettings) -> Bool {
        (try? readSettings(at: url)).map { isInstalled(in: $0, bridgePath: bridgePath) } ?? false
    }
}
