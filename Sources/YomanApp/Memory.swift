import Darwin
import Foundation

/// Hands freed heap pages back to macOS after bursts of work (hook messages, menus, Settings), so the
/// footprint shown in Activity Monitor drops back to what the cat actually uses.
enum Memory {
    private static var pending = false

    /// Coalesced: runs once, a couple of seconds after the last request.
    static func relieveSoon() {
        guard !pending else { return }
        pending = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            pending = false
            malloc_zone_pressure_relief(nil, 0)
        }
    }
}
