import Foundation

/// User settings, stored in UserDefaults (the Settings window binds to the same keys with @AppStorage).
enum Prefs {
    enum Key {
        static let name = "yoman.name"
        static let size = "yoman.size"
        static let sounds = "yoman.sounds"
        static let typing = "yoman.typing"
        static let scrollPaper = "yoman.scrollPaper"
        static let petting = "yoman.petting"
        static let stretchOn = "yoman.stretchOn"
        static let stretchMinutes = "yoman.stretchMinutes"
        static let waterOn = "yoman.waterOn"
        static let waterMinutes = "yoman.waterMinutes"
        static let peek = "yoman.peek"
        static let focusMinutes = "yoman.focusMinutes"
        static let breakMinutes = "yoman.breakMinutes"
        static let longBreakMinutes = "yoman.longBreakMinutes"
        static let pinned = "yoman.pinned"
        static let messages = "yoman.messages"
        static let music = "yoman.music"
        static let songTitle = "yoman.songTitle"
        static let sleepSeconds = "yoman.sleepSeconds"
        static let batterySaver = "yoman.batterySaver"
        static let catColor = "yoman.catColor"
    }

    static func register() {
        UserDefaults.standard.register(defaults: [
            Key.name: "Jagoan", Key.size: 2, Key.sounds: false, Key.typing: true, Key.scrollPaper: true,
            Key.petting: true, Key.stretchOn: true, Key.stretchMinutes: 50,
            Key.waterOn: true, Key.waterMinutes: 60, Key.peek: true, Key.focusMinutes: 25,
            Key.breakMinutes: 5, Key.longBreakMinutes: 15, Key.pinned: "", Key.music: true, Key.songTitle: true,
            Key.sleepSeconds: 15, Key.batterySaver: true, Key.catColor: "black",
        ])
    }

    private static var d: UserDefaults { .standard }
    static var name: String {
        let n = d.string(forKey: Key.name)?.trimmingCharacters(in: .whitespaces) ?? ""
        return n.isEmpty ? "Jagoan" : n
    }
    static var size: Int { min(4, max(1, d.integer(forKey: Key.size))) }
    static var sounds: Bool { d.bool(forKey: Key.sounds) }
    static var typing: Bool { d.bool(forKey: Key.typing) }
    static var scrollPaper: Bool { d.bool(forKey: Key.scrollPaper) }
    static var petting: Bool { d.bool(forKey: Key.petting) }
    static var stretchOn: Bool { d.bool(forKey: Key.stretchOn) }
    static var stretchMinutes: Int { max(5, d.integer(forKey: Key.stretchMinutes)) }
    static var waterOn: Bool { d.bool(forKey: Key.waterOn) }
    static var waterMinutes: Int { max(5, d.integer(forKey: Key.waterMinutes)) }
    static var peek: Bool { d.bool(forKey: Key.peek) }
    static var music: Bool { d.bool(forKey: Key.music) }
    static var songTitle: Bool { d.bool(forKey: Key.songTitle) }
    static var batterySaver: Bool { d.bool(forKey: Key.batterySaver) }
    /// "black" (default) or "white".
    static var catColor: String { d.string(forKey: Key.catColor) == "white" ? "white" : "black" }
    static var sleepSeconds: Int { max(5, d.integer(forKey: Key.sleepSeconds)) }
    static var focusMinutes: Int { max(1, d.integer(forKey: Key.focusMinutes)) }
    static var breakMinutes: Int { max(1, d.integer(forKey: Key.breakMinutes)) }
    static var longBreakMinutes: Int { max(1, d.integer(forKey: Key.longBreakMinutes)) }
    static var pinned: String {
        get { d.string(forKey: Key.pinned) ?? "" }
        set { d.set(newValue, forKey: Key.pinned) }
    }
}
