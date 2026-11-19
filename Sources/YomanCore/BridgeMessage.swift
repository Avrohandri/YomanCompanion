import Foundation

/// The small, privacy-trimmed summary of one Claude Code hook call that the bridge sends to the app.
/// Prompt text, tool inputs and tool outputs are never forwarded.
public struct BridgeMessage: Codable, Equatable, Sendable {
    public var event: String
    public var sessionID: String
    /// PID of the Claude Code process that ran the hook, for the liveness watchdog.
    public var pid: Int32?
    /// Last path component of the session's working directory (the project name).
    public var project: String?
    public var tool: String?
    public var notificationType: String?
    /// `CLAUDE_CODE_ENTRYPOINT`, e.g. "cli" or "claude-desktop".
    public var entrypoint: String?
    /// Bundle id of the app hosting the session (terminal or Claude desktop), used to bring it forward.
    public var sourceBundleID: String?

    public init(
        event: String, sessionID: String, pid: Int32? = nil, project: String? = nil, tool: String? = nil,
        notificationType: String? = nil, entrypoint: String? = nil, sourceBundleID: String? = nil
    ) {
        self.event = event
        self.sessionID = sessionID
        self.pid = pid
        self.project = project
        self.tool = tool
        self.notificationType = notificationType
        self.entrypoint = entrypoint
        self.sourceBundleID = sourceBundleID
    }

    /// Builds a message from a hook's stdin JSON and the hook process environment.
    /// Returns nil when the payload is not a hook event.
    public static func from(payload: Data, env: [String: String], fallbackPID: Int32?) -> BridgeMessage? {
        guard let obj = try? JSONSerialization.jsonObject(with: payload) as? [String: Any],
              let event = obj["hook_event_name"] as? String
        else { return nil }
        let session = (obj["session_id"] as? String) ?? "unknown"
        let project = (obj["cwd"] as? String).map { URL(fileURLWithPath: $0).lastPathComponent }
        let pid = env["CLAUDE_PID"].flatMap { Int32($0) } ?? fallbackPID
        return BridgeMessage(
            event: event,
            sessionID: session,
            pid: pid,
            project: project,
            tool: obj["tool_name"] as? String,
            notificationType: obj["notification_type"] as? String,
            entrypoint: env["CLAUDE_CODE_ENTRYPOINT"],
            sourceBundleID: env["__CFBundleIdentifier"]
        )
    }
}
