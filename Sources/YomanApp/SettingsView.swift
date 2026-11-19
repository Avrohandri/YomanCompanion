import AppKit

/// Settings in plain AppKit (no SwiftUI, which would add ~18 MB the first time the window opens).
/// Every control reads and writes UserDefaults directly; the app picks changes up from there.
final class SettingsWindowController: NSObject, NSWindowDelegate, NSTextFieldDelegate {
    private var window: NSWindow?
    private var trustTimer: Timer?
    private var permissionRow: NSView?
    /// Steppers whose labels show their value; enabled/disabled by a toggle.
    private var steppers: [(NSStepper, NSTextField, (Int) -> String, String?)] = []
    private var toggles: [String: NSButton] = [:]
    /// Toggles greyed out while their parent toggle is off (key → parent key).
    private var toggleParents: [String: String] = [:]
    private let d = UserDefaults.standard

    func show() {
        if window == nil { build() }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    /// Drop the window and every control when closed, so nothing stays in memory.
    func windowWillClose(_ notification: Notification) {
        trustTimer?.invalidate()
        trustTimer = nil
        DispatchQueue.main.async {
            self.window = nil
            self.permissionRow = nil
            self.steppers.removeAll()
            self.toggles.removeAll()
            self.toggleParents.removeAll()
            Memory.relieveSoon()
        }
    }

    func close() { window?.close() }

    /// Renders the window's content for visual checks (no screen-recording permission needed).
    func snapshot(to url: URL) {
        guard let w = window, let v = w.contentView, let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) else { return }
        let old = w.appearance
        w.appearance = NSAppearance(named: .aqua)  // the cached render has no window background, so use dark text
        v.layoutSubtreeIfNeeded()
        v.cacheDisplay(in: v.bounds, to: rep)
        w.appearance = old
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }

    // MARK: Layout

    private func build() {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 18, left: 20, bottom: 20, right: 20)

        stack.addArrangedSubview(header("You"))
        let name = NSTextField(string: d.string(forKey: Prefs.Key.name) ?? "Jagoan")
        name.placeholderString = "Jagoan"
        name.delegate = self
        name.widthAnchor.constraint(equalToConstant: 220).isActive = true
        stack.addArrangedSubview(row(label("Your name"), name))
        let size = NSSegmentedControl(labels: ["Small", "Medium", "Large"], trackingMode: .selectOne,
                                      target: self, action: #selector(sizeChanged(_:)))
        size.selectedSegment = min(2, max(0, Prefs.size - 1))
        stack.addArrangedSubview(row(label("Cat size"), size))
        stack.addArrangedSubview(stepper(Prefs.Key.sleepSeconds, 5...600, step: 5) { "Sleep after \($0) s without input" })

        stack.addArrangedSubview(header("Reactions"))
        stack.addArrangedSubview(toggle(Prefs.Key.sounds, "Sounds (meow, purr)"))
        stack.addArrangedSubview(toggle(Prefs.Key.typing, "Knead while I type"))
        let note = label("Needs Input Monitoring permission. Only the timing of key presses is used, never which keys.")
        note.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        note.textColor = .secondaryLabelColor
        note.preferredMaxLayoutWidth = 300
        note.lineBreakMode = .byWordWrapping
        let grant = NSButton(title: "Grant…", target: self, action: #selector(grantAccess))
        let perm = row(note, grant)
        permissionRow = perm
        stack.addArrangedSubview(perm)
        stack.addArrangedSubview(toggle(Prefs.Key.scrollPaper, "Bat a paper roll when I scroll"))
        stack.addArrangedSubview(toggle(Prefs.Key.petting, "Purr when petted (wiggle the cursor over its head)"))
        stack.addArrangedSubview(toggle(Prefs.Key.peek, "Peek from the screen edge in full screen"))
        stack.addArrangedSubview(toggle(Prefs.Key.batterySaver, "Battery saver on battery / Low Power Mode (no eye tracking)"))
        stack.addArrangedSubview(toggle(Prefs.Key.music, "Vibe to Apple Music / Spotify"))
        stack.addArrangedSubview(toggle(Prefs.Key.songTitle, "Show the song title when a track starts", dependsOn: Prefs.Key.music))

        stack.addArrangedSubview(header("Reminders"))
        stack.addArrangedSubview(toggle(Prefs.Key.stretchOn, "Stretch reminder"))
        stack.addArrangedSubview(stepper(Prefs.Key.stretchMinutes, 10...180, step: 5, dependsOn: Prefs.Key.stretchOn) {
            "Every \($0) minutes" })
        stack.addArrangedSubview(toggle(Prefs.Key.waterOn, "Drink water reminder"))
        stack.addArrangedSubview(stepper(Prefs.Key.waterMinutes, 10...180, step: 5, dependsOn: Prefs.Key.waterOn) {
            "Every \($0) minutes" })

        stack.addArrangedSubview(header("Pomodoro"))
        stack.addArrangedSubview(stepper(Prefs.Key.focusMinutes, 5...90, step: 5) { "Focus: \($0) min" })
        stack.addArrangedSubview(stepper(Prefs.Key.breakMinutes, 1...30, step: 1) { "Break: \($0) min" })
        stack.addArrangedSubview(stepper(Prefs.Key.longBreakMinutes, 5...60, step: 5) { "Long break (every 4th): \($0) min" })

        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: 600),
                         styleMask: [.titled, .closable], backing: .buffered, defer: false)
        w.title = "Yoman Settings"
        w.contentView = stack
        w.isReleasedWhenClosed = false
        w.delegate = self
        window = w
        refreshEnabled()
        updatePermission()
        w.setContentSize(stack.fittingSize)
        w.center()

        let t = Timer(timeInterval: 2, repeats: true) { [weak self] _ in self?.updatePermission() }
        t.tolerance = 0.5
        RunLoop.main.add(t, forMode: .common)
        trustTimer = t
    }

    private func header(_ s: String) -> NSView {
        let l = label(s)
        l.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
        let wrap = NSStackView(views: [l])
        wrap.edgeInsets = NSEdgeInsets(top: 8, left: 0, bottom: 0, right: 0)
        return wrap
    }

    private func label(_ s: String) -> NSTextField {
        let l = NSTextField(wrappingLabelWithString: s)
        l.isSelectable = false
        return l
    }

    private func row(_ views: NSView...) -> NSStackView {
        let r = NSStackView(views: views)
        r.orientation = .horizontal
        r.spacing = 10
        return r
    }

    private func toggle(_ key: String, _ title: String, dependsOn: String? = nil) -> NSButton {
        let b = NSButton(checkboxWithTitle: title, target: self, action: #selector(toggled(_:)))
        b.identifier = NSUserInterfaceItemIdentifier(key)
        b.state = d.bool(forKey: key) ? .on : .off
        toggles[key] = b
        if let dep = dependsOn { toggleParents[key] = dep }
        return b
    }

    private func stepper(_ key: String, _ range: ClosedRange<Int>, step: Int, dependsOn: String? = nil,
                         text: @escaping (Int) -> String) -> NSView {
        let s = NSStepper()
        s.minValue = Double(range.lowerBound)
        s.maxValue = Double(range.upperBound)
        s.increment = Double(step)
        s.valueWraps = false
        s.integerValue = min(range.upperBound, max(range.lowerBound, d.integer(forKey: key)))
        s.identifier = NSUserInterfaceItemIdentifier(key)
        s.target = self
        s.action = #selector(stepped(_:))
        let l = label(text(s.integerValue))
        steppers.append((s, l, text, dependsOn))
        return row(l, s)
    }

    // MARK: Actions

    @objc private func toggled(_ b: NSButton) {
        guard let key = b.identifier?.rawValue else { return }
        d.set(b.state == .on, forKey: key)
        refreshEnabled()
        updatePermission()
    }

    @objc private func stepped(_ s: NSStepper) {
        guard let key = s.identifier?.rawValue else { return }
        d.set(s.integerValue, forKey: key)
        if let e = steppers.first(where: { $0.0 === s }) { e.1.stringValue = e.2(s.integerValue) }
    }

    @objc private func sizeChanged(_ c: NSSegmentedControl) {
        d.set(c.selectedSegment + 1, forKey: Prefs.Key.size)
    }

    func controlTextDidChange(_ obj: Notification) {
        guard let f = obj.object as? NSTextField else { return }
        d.set(f.stringValue, forKey: Prefs.Key.name)
    }

    @objc private func grantAccess() {
        KeyListener.requestAccess()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
            NSWorkspace.shared.open(url)
        }
    }

    private func refreshEnabled() {
        for (key, dep) in toggleParents { toggles[key]?.isEnabled = d.bool(forKey: dep) }
        for (s, l, _, dep) in steppers {
            let on = dep.map { d.bool(forKey: $0) } ?? true
            s.isEnabled = on
            l.textColor = on ? .labelColor : .disabledControlTextColor
        }
    }

    private func updatePermission() {
        permissionRow?.isHidden = !(Prefs.typing && !KeyListener.hasAccess)
    }
}
