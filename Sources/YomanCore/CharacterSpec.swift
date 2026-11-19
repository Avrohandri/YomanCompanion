import Foundation

/// A character pack: one sprite sheet (one row per state, frames left to right) plus this description.
/// Modeled on waifu-assistance's `pet.json`.
public struct CharacterSpec: Codable, Sendable, Equatable {
    public struct StateSpec: Codable, Sendable, Equatable {
        public var row: Int
        public var frames: [Int]
        public var durationsMs: [Int]
        public var loop: Bool
        /// Whether the separate pupil layer is drawn (false for closed-eye frames).
        public var eyes: Bool?
        /// State to switch to when a non-looping animation ends (default: "idle").
        public var next: String?
        /// Per-frame [dx, dy] shift of the pupils, so they move with head bobs and jumps.
        public var eyeOffsets: [[Int]]?
    }

    public struct EyesSpec: Codable, Sendable, Equatable {
        /// Top-left pixel of each pupil at rest, in cell pixels (origin top-left).
        public var left: [Int]
        public var right: [Int]
        /// Pupil size in pixels [w, h].
        public var pupil: [Int]
        /// Max whole-pixel shift toward the cursor [dx, dy].
        public var range: [Int]
        /// Hex color, e.g. "#2E6B4F".
        public var color: String
    }

    public var name: String
    public var sheet: String
    public var cellWidth: Int
    public var cellHeight: Int
    /// Default on-screen points per art pixel.
    public var scale: Int
    public struct PaperSpec: Codable, Sendable, Equatable {
        /// Art-pixel point where the scroll paper strip starts; it unrolls leftward along the floor.
        public var x: Int
        public var y: Int
        public var height: Int
    }

    public var states: [String: StateSpec]
    public var eyes: EyesSpec?
    public var paper: PaperSpec?

    public static func load(from dir: URL) throws -> CharacterSpec {
        let data = try Data(contentsOf: dir.appendingPathComponent("character.json"))
        let dec = JSONDecoder()
        dec.keyDecodingStrategy = .convertFromSnakeCase
        return try dec.decode(CharacterSpec.self, from: data)
    }

    /// Problems that would break rendering; empty when the pack is usable.
    public func validate() -> [String] {
        var issues: [String] = []
        if states["idle"] == nil { issues.append("missing required state 'idle'") }
        for (name, s) in states {
            if s.frames.isEmpty { issues.append("\(name): no frames") }
            if s.frames.count != s.durationsMs.count { issues.append("\(name): frames/durations length mismatch") }
            if s.durationsMs.contains(where: { $0 <= 0 }) { issues.append("\(name): durations must be > 0") }
            if let n = s.next, states[n] == nil { issues.append("\(name): next state '\(n)' not defined") }
            if let o = s.eyeOffsets, o.count != s.frames.count { issues.append("\(name): eye_offsets length mismatch") }
        }
        return issues
    }
}
