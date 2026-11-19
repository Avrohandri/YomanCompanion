import Foundation

/// What the companion should express about Claude Code overall.
public enum ClaudeMood: String, Sendable, Equatable {
    case none       // no live session
    case idle       // sessions open, nothing happening
    case working
    case needsYou
    case done
}

/// A one-shot reaction triggered by a single event (on top of the steady mood).
public enum ClaudeReaction: Sendable, Equatable {
    case greet
    case finished(project: String?)
    case needsYou(project: String?)
}

/// Tracks every live Claude Code session from hook events and folds them into one mood.
public struct SessionTracker: Sendable {
    public enum State: Sendable, Equatable { case idle, working, needsYou, done }

    public struct Session: Sendable, Equatable {
        public var id: String
        public var pid: Int32?
        public var project: String?
        public var sourceBundleID: String?
        public var state: State
        public var since: Date
    }

    /// How long "done" lingers before falling back to idle.
    public var doneHold: TimeInterval = 4
    /// A user interrupt (Esc) fires no Stop hook, so a stuck "working" decays after this long without events.
    public var workingTimeout: TimeInterval = 5 * 60
    public var needsYouTimeout: TimeInterval = 10 * 60

    public private(set) var sessions: [String: Session] = [:]

    public init() {}

    /// Tools whose PreToolUse means Claude is asking the user something.
    static let askingTools: Set<String> = ["AskUserQuestion", "ExitPlanMode"]

    @discardableResult
    public mutating func apply(_ m: BridgeMessage, now: Date = Date()) -> ClaudeReaction? {
        if m.event == "SessionEnd" {
            sessions[m.sessionID] = nil
            return nil
        }
        var s = sessions[m.sessionID]
            ?? Session(id: m.sessionID, pid: m.pid, project: m.project, sourceBundleID: m.sourceBundleID,
                       state: .idle, since: now)
        if let pid = m.pid { s.pid = pid }
        if let p = m.project { s.project = p }
        if let b = m.sourceBundleID { s.sourceBundleID = b }

        var reaction: ClaudeReaction?
        let next: State?
        switch m.event {
        case "SessionStart":
            next = .idle
            reaction = .greet
        case "UserPromptSubmit", "PostToolUse":
            next = .working
        case "PreToolUse":
            next = Self.askingTools.contains(m.tool ?? "") ? .needsYou : .working
        case "PermissionRequest":
            next = .needsYou
        case "Notification":
            // "idle_prompt" is Claude's 60 s "still waiting" nudge after a finished turn, not a request.
            next = m.notificationType == "idle_prompt" ? nil : .needsYou
        case "Stop":
            next = .done
            reaction = .finished(project: s.project)
        default:
            next = nil  // SubagentStop and unknown events don't change the main state
        }
        if let next, next != s.state {
            if next == .needsYou { reaction = .needsYou(project: s.project) }
            s.state = next
            s.since = now
        } else if next != nil {
            s.since = now
        }
        sessions[m.sessionID] = s
        return reaction
    }

    /// The effective state of one session at `now`, after timeouts.
    func effective(_ s: Session, now: Date) -> State {
        let age = now.timeIntervalSince(s.since)
        switch s.state {
        case .done: return age < doneHold ? .done : .idle
        case .working: return age < workingTimeout ? .working : .idle
        case .needsYou: return age < needsYouTimeout ? .needsYou : .idle
        case .idle: return .idle
        }
    }

    public func mood(now: Date = Date()) -> ClaudeMood {
        if sessions.isEmpty { return .none }
        let states = sessions.values.map { effective($0, now: now) }
        if states.contains(.needsYou) { return .needsYou }
        if states.contains(.working) { return .working }
        if states.contains(.done) { return .done }
        return .idle
    }

    /// The session most recently asking for the user, to bring its window forward.
    public func sessionNeedingYou(now: Date = Date()) -> Session? {
        sessions.values.filter { effective($0, now: now) == .needsYou }.max { $0.since < $1.since }
    }

    /// The most recently active session, as a fallback target for a click.
    public func latestSession() -> Session? {
        sessions.values.max { $0.since < $1.since }
    }

    /// Drops sessions whose Claude process died without sending SessionEnd. Returns how many were removed.
    @discardableResult
    public mutating func prune(isAlive: (Int32) -> Bool) -> Int {
        let dead = sessions.values.filter { s in s.pid.map { !isAlive($0) } ?? false }.map(\.id)
        dead.forEach { sessions[$0] = nil }
        return dead.count
    }

    /// Seconds until the mood can change by itself (a timeout expiring), or nil if nothing is pending.
    public func nextTimeout(now: Date = Date()) -> TimeInterval? {
        sessions.values.compactMap { s -> TimeInterval? in
            let age = now.timeIntervalSince(s.since)
            let limit: TimeInterval
            switch s.state {
            case .done: limit = doneHold
            case .working: limit = workingTimeout
            case .needsYou: limit = needsYouTimeout
            case .idle: return nil
            }
            return age < limit ? limit - age : nil
        }.min()
    }
}
