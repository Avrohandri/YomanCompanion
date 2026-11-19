import Foundation

/// Speech-bubble lines (English). `name` is what the cat calls you (Settings → Your name).
enum Lines {
    static var name: String { Prefs.name }

    static func launch(now: Date = Date()) -> String {
        switch Calendar.current.component(.hour, from: now) {
        case 5..<11: return "Mrrp! Morning, \(name)."
        case 11..<15: return "Meow. Afternoon, \(name)."
        case 15..<19: return "Evening, \(name). I'm here."
        default: return "Still up, \(name)? Me too."
        }
    }

    static var sessionStart: [String] { ["Mrrp? Claude's here.", "New session! I'll watch.", "Ooh, are we working?"] }

    static func finished(project: String?) -> String {
        let base = ["Meow! Claude's done, \(name).", "Done! Come look~", "Claude finished. Treat time?",
                    "All done, \(name)!"].randomElement()!
        guard let project, !project.isEmpty else { return base }
        return "\(base)\n(\(project))"
    }

    static func needsYou(project: String?) -> String {
        let base = "\(name)! Claude needs you."
        guard let project, !project.isEmpty else { return base + "\nClick me to go there." }
        return "\(base)\n(\(project)) Click me."
    }

    static var wake: [String] { ["...mrrp? Oh, you're back.", "*yawn* Hi, \(name).", "I wasn't sleeping."] }
    static var poked: [String] { ["Mrrp?", "Meow.", "Pet me instead~", "Keep going, \(name)!", "*stares*"] }
    static var petted: [String] { ["Purrrr...", "More, please.", "Mmm, right there."] }
    static var overheat: [String] { ["Too fast! I'm melting!", "Slow down, \(name)! Hot hot hot!"] }

    static var stretch: String { "Stretch time, \(name)!\nStand up and reach with me." }
    static var water: String { "Drink some water, \(name).\nI'm drinking too." }
    static var goodJob: [String] { ["Good job! Back to it.", "Nice! I feel better too.", "Purr. Healthy human."] }

    static func focusStart(_ m: Int) -> String { "Focus time: \(m) min.\nI'll guard you." }
    static func breakStart(_ m: Int, long: Bool) -> String {
        long ? "Long break! \(m) min.\nYou earned it." : "Break time! \(m) min.\nRest your eyes."
    }
    static var focusBack: String { "Break's over.\nLet's focus, \(name)." }
    static var pomodoroStopped: String { "Pomodoro stopped." }

    static func message(_ text: String) -> String { "Meow! Reminder:\n\(text)" }
    static var peek: String { "Enjoy the show, \(name)." }

    static func nowPlaying(_ name: String?, _ artist: String?) -> String {
        switch (name, artist) {
        case let (n?, a?) where !a.isEmpty: return "♪ \(n)\n\(a)"
        case let (n?, _): return "♪ \(n)"
        default: return "♪ Ooh, music!"
        }
    }
}
