import AppKit

/// A one-off reminder at a set time, with your own message.
struct ScheduledMessage: Codable, Equatable {
    var id = UUID()
    var text: String
    var date: Date
}

/// Stretch & water reminders, the Pomodoro loop and timed messages. Talks to the cat through callbacks.
final class Reminders {
    enum Phase: Equatable { case focus, shortBreak, longBreak }

    var onStretch: (() -> Void)?
    var onWater: (() -> Void)?
    var onSay: ((String) -> Void)?
    var onMessage: ((String) -> Void)?
    /// Pomodoro countdown text for the tag above the cat and the menu bar ("Focus 24:13"), or nil.
    var onTimerText: ((String?) -> Void)?

    private var stretchTimer: Timer?
    private var waterTimer: Timer?
    private var messageTimers: [UUID: Timer] = [:]
    private var applied: (Bool, Int, Bool, Int)?

    private(set) var phase: Phase?
    private var phaseEnd = Date()
    private var completedFocus = 0
    private var tickTimer: Timer?

    // MARK: Stretch & water

    /// Re-arms the interval timers when their settings changed (cheap to call often).
    func applyPrefs() {
        let now = (Prefs.stretchOn, Prefs.stretchMinutes, Prefs.waterOn, Prefs.waterMinutes)
        if let a = applied, a == now { return }
        applied = now
        stretchTimer?.invalidate()
        waterTimer?.invalidate()
        stretchTimer = now.0 ? repeating(minutes: now.1) { [weak self] in self?.fire(self?.onStretch) } : nil
        waterTimer = now.2 ? repeating(minutes: now.3) { [weak self] in self?.fire(self?.onWater) } : nil
    }

    private func repeating(minutes: Int, _ block: @escaping () -> Void) -> Timer {
        let t = Timer(timeInterval: TimeInterval(minutes * 60), repeats: true) { _ in block() }
        t.tolerance = 30
        RunLoop.main.add(t, forMode: .common)
        return t
    }

    /// Skips the reminder when you're away from the Mac (no input for 5 minutes) or in a focus block's break logic.
    private func fire(_ action: (() -> Void)?) {
        let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
        guard idle < 5 * 60 else { return }
        action?()
    }

    /// For testing from the menu.
    func triggerStretchNow() { onStretch?() }
    func triggerWaterNow() { onWater?() }

    // MARK: Pomodoro

    var isRunning: Bool { phase != nil }

    func startFocus() { start(.focus) }
    func startBreak() { start(.shortBreak) }

    func stop() {
        phase = nil
        completedFocus = 0
        tickTimer?.invalidate()
        tickTimer = nil
        onTimerText?(nil)
        onSay?(Lines.pomodoroStopped)
    }

    private func minutes(_ p: Phase) -> Int {
        switch p {
        case .focus: return Prefs.focusMinutes
        case .shortBreak: return Prefs.breakMinutes
        case .longBreak: return Prefs.longBreakMinutes
        }
    }

    private func start(_ p: Phase) {
        phase = p
        phaseEnd = Date().addingTimeInterval(TimeInterval(minutes(p) * 60))
        switch p {
        case .focus: onSay?(Lines.focusStart(minutes(p)))
        case .shortBreak, .longBreak: onSay?(Lines.breakStart(minutes(p), long: p == .longBreak))
        }
        tickTimer?.invalidate()
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
        t.tolerance = 0.2
        RunLoop.main.add(t, forMode: .common)
        tickTimer = t
        tick()
    }

    private func tick() {
        guard let phase else { return }
        let left = Int(ceil(phaseEnd.timeIntervalSinceNow))
        if left <= 0 {
            Sounds.play(Sounds.mrrp)
            switch phase {
            case .focus:
                completedFocus += 1
                start(completedFocus % 4 == 0 ? .longBreak : .shortBreak)
            case .shortBreak, .longBreak:
                onSay?(Lines.focusBack)
                start(.focus)
            }
            return
        }
        let label = phase == .focus ? "Focus" : "Break"
        onTimerText?(String(format: "%@ %d:%02d", label, left / 60, left % 60))
    }

    // MARK: Timed messages

    private(set) var messages: [ScheduledMessage] = []

    func loadMessages() {
        if let data = UserDefaults.standard.data(forKey: Prefs.Key.messages),
           let list = try? JSONDecoder().decode([ScheduledMessage].self, from: data) {
            messages = list
        }
        // Ones that came due while the app wasn't running are shown now.
        messages.forEach(arm)
    }

    func add(_ text: String, at date: Date) {
        let m = ScheduledMessage(text: text, date: date)
        messages.append(m)
        messages.sort { $0.date < $1.date }
        save()
        arm(m)
    }

    func cancel(_ id: UUID) {
        messageTimers[id]?.invalidate()
        messageTimers[id] = nil
        messages.removeAll { $0.id == id }
        save()
    }

    private func arm(_ m: ScheduledMessage) {
        let t = Timer(fire: max(Date().addingTimeInterval(2), m.date), interval: 0, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.onMessage?(m.text)
            self.cancel(m.id)
        }
        t.tolerance = 1
        RunLoop.main.add(t, forMode: .common)
        messageTimers[m.id] = t
    }

    private func save() {
        if let data = try? JSONEncoder().encode(messages) {
            UserDefaults.standard.set(data, forKey: Prefs.Key.messages)
        }
    }
}
