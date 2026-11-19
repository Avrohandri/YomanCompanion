import AppKit

/// Notices when the frontmost app goes full screen (e.g. a video) so the cat can peek from the edge.
/// Event-driven: it only checks when the active app or Space changes. Reading window bounds needs no permission.
final class FullscreenWatcher {
    var onChange: ((NSScreen?) -> Void)?
    private var current: NSScreen?
    private var observers: [NSObjectProtocol] = []

    func start() {
        let nc = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.didActivateApplicationNotification] {
            observers.append(nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.checkSoon()
            })
        }
        check()
    }

    func stop() {
        observers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
        observers.removeAll()
    }

    /// Full-screen transitions animate for ~0.7 s, so check again once they settle.
    private func checkSoon() {
        check()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in self?.check() }
    }

    func check() {
        let screen = fullscreenScreen()
        guard screen != current else { return }
        current = screen
        onChange?(screen)
    }

    private func fullscreenScreen() -> NSScreen? {
        guard let front = NSWorkspace.shared.frontmostApplication,
              front.bundleIdentifier != Bundle.main.bundleIdentifier,
              let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]]
        else { return nil }
        let mainHeight = NSScreen.screens.first?.frame.height ?? 0
        for w in list where (w[kCGWindowOwnerPID as String] as? pid_t) == front.processIdentifier
            && (w[kCGWindowLayer as String] as? Int) == 0 {
            guard let b = w[kCGWindowBounds as String] as? [String: CGFloat],
                  let x = b["X"], let y = b["Y"], let width = b["Width"], let height = b["Height"]
            else { continue }
            // CG window coordinates are top-left based; convert to AppKit's bottom-left.
            let rect = NSRect(x: x, y: mainHeight - y - height, width: width, height: height)
            if let s = NSScreen.screens.first(where: { $0.frame.equalTo(rect) }) { return s }
        }
        return nil
    }
}
