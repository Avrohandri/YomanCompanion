import AppKit

/// The cat's sounds: synthesized meow/mrrp from the bundle, plus macOS's built-in "Purr".
enum Sounds {
    private static func bundled(_ name: String) -> NSSound? {
        guard let url = Bundle.main.resourceURL?.appendingPathComponent("sounds/\(name).wav") else { return nil }
        let s = NSSound(contentsOf: url, byReference: true)
        s?.volume = 0.55
        return s
    }

    static let meow = bundled("meow")
    static let mrrp = bundled("mrrp")
    static let purr: NSSound? = {
        let s = NSSound(named: "Purr")
        s?.volume = 0.5
        return s
    }()

    static func play(_ s: NSSound?) {
        guard Prefs.sounds, let s else { return }
        s.stop()
        s.play()
    }
}
