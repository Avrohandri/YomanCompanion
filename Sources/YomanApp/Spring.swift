import Foundation

/// A damped spring toward `target`, stepped by the display link while something is moving.
struct Spring {
    var value: Double
    var velocity: Double = 0
    var target: Double
    var stiffness: Double
    var damping: Double

    init(_ v: Double, stiffness: Double = 260, damping: Double = 12) {
        value = v
        target = v
        self.stiffness = stiffness
        self.damping = damping
    }

    mutating func step(_ dt: Double) {
        // Semi-implicit Euler in small sub-steps so a long frame can't explode the spring.
        var left = dt
        while left > 0 {
            let h = min(left, 1.0 / 240)
            velocity += (-stiffness * (value - target) - damping * velocity) * h
            value += velocity * h
            left -= h
        }
    }

    var settled: Bool { abs(value - target) < 0.001 && abs(velocity) < 0.01 }

    mutating func snap() {
        value = target
        velocity = 0
    }
}
