import Foundation
import Testing
@testable import YomanCore

private func msg(_ event: String, _ session: String = "s1", tool: String? = nil, note: String? = nil) -> BridgeMessage {
    BridgeMessage(event: event, sessionID: session, pid: 42, project: "demo", tool: tool, notificationType: note)
}

@Suite struct BridgeMessageTests {
    @Test func parsesHookPayloadAndDropsContent() throws {
        let payload = """
        {"hook_event_name":"PreToolUse","session_id":"abc","cwd":"/Users/x/Projects/Cool","tool_name":"Bash",
         "tool_input":{"command":"rm -rf secret"},"prompt":"private"}
        """
        let env = ["CLAUDE_PID": "999", "CLAUDE_CODE_ENTRYPOINT": "claude-desktop",
                   "__CFBundleIdentifier": "com.anthropic.claudefordesktop"]
        let m = try #require(BridgeMessage.from(payload: Data(payload.utf8), env: env, fallbackPID: 1))
        #expect(m == BridgeMessage(event: "PreToolUse", sessionID: "abc", pid: 999, project: "Cool", tool: "Bash",
                                   entrypoint: "claude-desktop", sourceBundleID: "com.anthropic.claudefordesktop"))
        let encoded = String(decoding: try JSONEncoder().encode(m), as: UTF8.self)
        #expect(!encoded.contains("secret") && !encoded.contains("private"))
    }

    @Test func rejectsNonHookInput() {
        #expect(BridgeMessage.from(payload: Data("{}".utf8), env: [:], fallbackPID: nil) == nil)
        #expect(BridgeMessage.from(payload: Data("garbage".utf8), env: [:], fallbackPID: nil) == nil)
    }

    @Test func fallsBackToParentPID() throws {
        let m = try #require(BridgeMessage.from(
            payload: Data(#"{"hook_event_name":"Stop","session_id":"a"}"#.utf8), env: [:], fallbackPID: 7))
        #expect(m.pid == 7)
    }
}

@Suite struct SessionTrackerTests {
    let t0 = Date(timeIntervalSince1970: 1_000_000)

    @Test func lifecycle() {
        var t = SessionTracker()
        #expect(t.mood(now: t0) == .none)
        #expect(t.apply(msg("SessionStart"), now: t0) == .greet)
        #expect(t.mood(now: t0) == .idle)
        t.apply(msg("UserPromptSubmit"), now: t0)
        #expect(t.mood(now: t0) == .working)
        #expect(t.apply(msg("PermissionRequest"), now: t0) == .needsYou(project: "demo"))
        #expect(t.mood(now: t0) == .needsYou)
        t.apply(msg("PostToolUse"), now: t0)
        #expect(t.mood(now: t0) == .working)
        #expect(t.apply(msg("Stop"), now: t0) == .finished(project: "demo"))
        #expect(t.mood(now: t0) == .done)
        #expect(t.mood(now: t0.addingTimeInterval(5)) == .idle)
        t.apply(msg("SessionEnd"), now: t0)
        #expect(t.mood(now: t0) == .none)
    }

    @Test func askUserQuestionNeedsYouButIdleNudgeDoesNot() {
        var t = SessionTracker()
        t.apply(msg("PreToolUse", tool: "AskUserQuestion"), now: t0)
        #expect(t.mood(now: t0) == .needsYou)
        var u = SessionTracker()
        u.apply(msg("Stop"), now: t0)
        u.apply(msg("Notification", note: "idle_prompt"), now: t0.addingTimeInterval(60))
        #expect(u.mood(now: t0.addingTimeInterval(60)) == .idle)
        u.apply(msg("Notification", note: "permission_prompt"), now: t0.addingTimeInterval(61))
        #expect(u.mood(now: t0.addingTimeInterval(61)) == .needsYou)
    }

    @Test func needsYouWinsAcrossSessions() {
        var t = SessionTracker()
        t.apply(msg("UserPromptSubmit", "a"), now: t0)
        t.apply(msg("PermissionRequest", "b"), now: t0)
        #expect(t.mood(now: t0) == .needsYou)
        #expect(t.sessionNeedingYou(now: t0)?.id == "b")
    }

    @Test func interruptedWorkDecays() {
        var t = SessionTracker()
        t.apply(msg("UserPromptSubmit"), now: t0)
        #expect(t.nextTimeout(now: t0) == t.workingTimeout)
        #expect(t.mood(now: t0.addingTimeInterval(t.workingTimeout + 1)) == .idle)
    }

    @Test func pruneDeadProcesses() {
        var t = SessionTracker()
        t.apply(msg("SessionStart", "a"), now: t0)
        t.apply(BridgeMessage(event: "SessionStart", sessionID: "b", pid: 43), now: t0)
        #expect(t.prune { $0 == 43 } == 1)
        #expect(t.sessions.keys.sorted() == ["b"])
    }
}

@Suite struct HookInstallerTests {
    let bridge = "/Users/x/Applications/Yoman.app/Contents/MacOS/yoman-bridge"

    @Test func installKeepsOtherHooksAndIsIdempotent() {
        let original: [String: Any] = [
            "theme": "dark",
            "hooks": ["Stop": [["hooks": [["type": "command", "command": "say done"]]]]],
        ]
        let once = HookInstaller.installing(into: original, bridgePath: bridge)
        let twice = HookInstaller.installing(into: once, bridgePath: bridge)
        #expect((once as NSDictionary).isEqual(to: twice))
        #expect(HookInstaller.isInstalled(in: once, bridgePath: bridge))
        #expect(!HookInstaller.isInstalled(in: once, bridgePath: "/elsewhere/yoman-bridge"))
        let stop = (once["hooks"] as! [String: Any])["Stop"] as! [[String: Any]]
        #expect(stop.count == 2)
        #expect(once["theme"] as? String == "dark")
    }

    @Test func removeRestoresOriginal() {
        let original: [String: Any] = [
            "theme": "dark",
            "hooks": ["Stop": [["hooks": [["type": "command", "command": "say done"]]]]],
        ]
        let back = HookInstaller.removing(from: HookInstaller.installing(into: original, bridgePath: bridge))
        #expect((back as NSDictionary).isEqual(to: original))
        let empty = HookInstaller.removing(from: HookInstaller.installing(into: [:], bridgePath: bridge))
        #expect(empty.isEmpty)
    }

    @Test func fileRoundTripWithBackup() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("settings.json")
        try Data(#"{"theme":"dark"}"#.utf8).write(to: url)
        #expect(try HookInstaller.install(bridgePath: bridge, at: url))
        #expect(try !HookInstaller.install(bridgePath: bridge, at: url))  // unchanged
        #expect(HookInstaller.status(bridgePath: bridge, at: url))
        #expect(FileManager.default.fileExists(atPath: url.path + ".yoman-backup"))
        #expect(try HookInstaller.remove(at: url))
        #expect(try HookInstaller.readSettings(at: url) as NSDictionary == ["theme": "dark"] as NSDictionary)
    }

    @Test func refusesInvalidJSON() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        try Data("{ not json".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(throws: HookInstaller.InstallError.self) { try HookInstaller.install(bridgePath: bridge, at: url) }
        #expect(String(decoding: try Data(contentsOf: url), as: UTF8.self) == "{ not json")
    }
}

@Suite struct CharacterSpecTests {
    @Test func validatesStates() throws {
        let json = """
        {"name":"t","sheet":"s.png","cell_width":64,"cell_height":64,"scale":3,
         "states":{"idle":{"row":0,"frames":[0,1],"durations_ms":[500,500],"loop":true},
                   "done":{"row":1,"frames":[0],"durations_ms":[300],"loop":false,"next":"nope"}}}
        """
        let dec = JSONDecoder()
        dec.keyDecodingStrategy = .convertFromSnakeCase
        let spec = try dec.decode(CharacterSpec.self, from: Data(json.utf8))
        #expect(spec.validate() == ["done: next state 'nope' not defined"])
    }
}
