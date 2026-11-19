import AppKit
import ServiceManagement
import YomanCore

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var assets: CharacterAssets!
    private var companion: CompanionController!
    private var server: SocketServer?
    private var hotKey: HotKey?
    private var statusItem: NSStatusItem!
    private var monitors: [Any] = []
    private let power = PowerWatcher()
    private var mouseTimer: Timer?
    private var mouseInterval: TimeInterval = 0
    private var lastMouse = NSPoint(x: -1, y: -1)
    private lazy var keys = KeyListener { [weak self] in self?.companion.keyPressed() }
    private var tracker = SessionTracker()
    private var moodTimer: Timer?
    private var watchdog: Timer?
    private let reminders = Reminders()
    private let fullscreen = FullscreenWatcher()
    private let music = MusicWatcher()
    private let settings = SettingsWindowController()
    private var appliedSize = 0
    private var trustTimer: Timer?

    private static let visibleKey = "yoman.visible"
    private static let loginInitKey = "yoman.loginItemInitialized"

    private var bridgePath: String {
        Bundle.main.executableURL!.deletingLastPathComponent().appendingPathComponent("yoman-bridge").path
    }

    func applicationDidFinishLaunching(_ note: Notification) {
        NSApp.setActivationPolicy(.accessory)
        Prefs.register()

        let server = SocketServer { [weak self] data in self?.handle(data) }
        do {
            try server.start()
        } catch SocketServer.StartError.alreadyRunning {
            NSApp.terminate(nil)
            return
        } catch {
            NSLog("Yoman: socket failed: \(error)")
        }
        self.server = server

        guard let dir = CharacterAssets.defaultDirectory(), let assets = try? CharacterAssets(dir: dir) else {
            let alert = NSAlert()
            alert.messageText = "Yoman couldn't load its character."
            alert.informativeText = "Expected a character pack (character.json + sheet) in the app's Resources."
            alert.runModal()
            NSApp.terminate(nil)
            return
        }
        self.assets = assets
        buildCompanion()

        setUpStatusItem()
        hotKey = HotKey.toggleCompanion { [weak self] in self?.toggleVisible() }
        enableLoginItemOnFirstRun()
        wireReminders()
        fullscreen.onChange = { [weak self] screen in self?.companion.setFullscreen(screen) }
        music.onChange = { [weak self] playing, track in self?.companion.setMusic(playing: playing, newTrack: track) }
        music.start()
        power.onChange = { [weak self] saving in
            self?.companion.saver = saving
            if self?.mouseTimer != nil { self?.startMousePolling() }
        }
        power.start()
        companion.saver = power.saving
        NotificationCenter.default.addObserver(self, selector: #selector(prefsChanged),
                                               name: UserDefaults.didChangeNotification, object: nil)

        let visible = UserDefaults.standard.object(forKey: Self.visibleKey) as? Bool ?? true
        if visible {
            showCompanion()
            companion.greetOnLaunch()
        }
    }

    func applicationWillTerminate(_ note: Notification) {
        server?.stop()
    }

    private func buildCompanion() {
        appliedSize = Prefs.size
        companion = CompanionController(assets: assets, scale: appliedSize)
        companion.onActivateClaude = { [weak self] in self?.bringClaudeForward() }
        companion.mood = tracker.mood()
        companion.setPinned(Prefs.pinned)
        companion.setMusic(playing: music.isPlaying, newTrack: nil)
        companion.saver = power.saving
    }

    @objc private func prefsChanged() {
        // didChangeNotification can arrive off the main thread and fires for every write; keep it cheap.
        DispatchQueue.main.async { [self] in
            reminders.applyPrefs()
            companion?.setMusic(playing: music.isPlaying, newTrack: nil)
            power.update()
            if Prefs.size != appliedSize, companion != nil {
                let wasVisible = companion.isVisible
                companion.hide()
                buildCompanion()
                if wasVisible { showCompanion() }
            }
            updateKeyMonitor()
        }
    }

    // MARK: Visibility & input monitors

    private func showCompanion() {
        companion.show()
        if monitors.isEmpty {
            let scroll: (NSEvent) -> Void = { [weak self] e in
                self?.companion.scrolled(dy: e.scrollingDeltaY, precise: e.hasPreciseScrollingDeltas)
            }
            if let s = NSEvent.addGlobalMonitorForEvents(matching: [.scrollWheel], handler: scroll) { monitors.append(s) }
        }
        updateKeyMonitor()
        fullscreen.start()
        startMousePolling()
        companion.cursorMoved(NSEvent.mouseLocation)
        UserDefaults.standard.set(true, forKey: Self.visibleKey)
    }

    private func hideCompanion() {
        companion.hide()
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        mouseTimer?.invalidate()
        mouseTimer = nil
        updateKeyMonitor()
        fullscreen.stop()
        UserDefaults.standard.set(false, forKey: Self.visibleKey)
    }

    /// The cursor is sampled on a timer instead of receiving every mouse event (up to ~120/s): 12 Hz while you're
    /// using the Mac, 2 Hz after 2 s without input, 4 Hz in battery saver or while Claude works (no eye tracking).
    /// Over the cat itself the window's tracking area still delivers every move, so petting stays responsive.
    private func startMousePolling() {
        let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
        // 4 Hz is enough for click-through and petting when the eyes aren't following the cursor.
        let calm = power.saving || companion.mood == .working
        let interval: TimeInterval = idle > 2 ? 0.5 : (calm ? 0.25 : 1.0 / 12)
        if mouseTimer == nil || interval != mouseInterval {
            mouseTimer?.invalidate()
            mouseInterval = interval
            let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in self?.pollMouse() }
            t.tolerance = interval * 0.2
            RunLoop.main.add(t, forMode: .common)
            mouseTimer = t
        }
    }

    private func pollMouse() {
        let p = NSEvent.mouseLocation
        if p != lastMouse {
            lastMouse = p
            companion.cursorMoved(p)
        }
        startMousePolling()  // adjusts the rate when activity or power state changed
    }

    /// Key presses (timing only) for kneading, via a listen-only event tap (Input Monitoring permission).
    private func updateKeyMonitor() {
        let want = companion?.isVisible == true && Prefs.typing
        guard want else {
            keys.stop()
            return
        }
        if keys.isRunning { return }
        if keys.start() {
            trustTimer?.invalidate()
            trustTimer = nil
            return
        }
        // No permission yet: poll, since the grant can arrive any time from System Settings.
        guard trustTimer == nil else { return }
        let t = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            guard let self, KeyListener.hasAccess else { return }
            self.trustTimer?.invalidate()
            self.trustTimer = nil
            if self.keys.start() {
                self.companion.say("Yay, I can feel your typing now!", for: 3)
            } else {
                // macOS often only lets a process tap keys after a relaunch once access is granted.
                self.relaunch()
            }
        }
        t.tolerance = 0.5
        RunLoop.main.add(t, forMode: .common)
        trustTimer = t
    }

    private func relaunch() {
        let path = Bundle.main.bundlePath
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "sleep 1; /usr/bin/open \"\(path)\""]
        try? task.run()
        NSApp.terminate(nil)
    }

    @objc private func toggleVisible() {
        companion.isVisible ? hideCompanion() : showCompanion()
    }

    // MARK: Reminders

    private func wireReminders() {
        reminders.onStretch = { [weak self] in self?.companion.remind(.stretch) }
        reminders.onWater = { [weak self] in self?.companion.remind(.drink) }
        reminders.onSay = { [weak self] text in self?.companion.say(text, for: 4) }
        reminders.onMessage = { [weak self] text in
            Sounds.play(Sounds.meow)
            self?.companion.playOneShot("greet")
            self?.companion.say(Lines.message(text), sticky: true)
        }
        reminders.onTimerText = { [weak self] text in
            self?.companion.setTimerText(text)
            self?.statusItem.button?.title = text.map { " " + $0 } ?? ""
        }
        reminders.applyPrefs()
        reminders.loadMessages()
    }

    // MARK: Claude Code events

    private func handle(_ data: Data) {
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let cmd = obj["debug"] as? String {
            debug(cmd)
            return
        }
        guard let m = try? JSONDecoder().decode(BridgeMessage.self, from: data) else { return }  // e.g. ping
        let reaction = tracker.apply(m)
        if let reaction { companion.react(reaction) }
        updateMood()
        ensureWatchdog()
    }

    /// Local-only test hooks (the socket is 0600): `yoman-bridge debug <cmd>`.
    private func debug(_ cmd: String) {
        switch cmd {
        case "status":
            let st: [String: Any] = ["batterySaver": power.saving, "mouseHz": mouseInterval > 0 ? (1 / mouseInterval).rounded() : 0,
                                     "accessibilityTrusted": AXIsProcessTrusted(), "listenAccess": CGPreflightListenEventAccess(),
                                     "keyTap": keys.isRunning,
                                     "typingPref": Prefs.typing, "visible": companion.isVisible,
                                     "state": companion.currentState, "y": companion.panelY]
            if let d = try? JSONSerialization.data(withJSONObject: st, options: [.sortedKeys]) {
                try? d.write(to: YomanPaths.logDir.appendingPathComponent("status.json"))
            }
        case "snapshot": companion.snapshot(to: YomanPaths.logDir.appendingPathComponent("snapshot.png"))
        case "stretch": reminders.triggerStretchNow()
        case "drink": reminders.triggerWaterNow()
        case "type": for _ in 0..<12 { companion.keyPressed() }
        case "overheat": for _ in 0..<30 { companion.keyPressed() }
        case "scroll": companion.scrolled(dy: 20, precise: false)
        case "peek": companion.setFullscreen(NSScreen.main)
        case "unpeek": companion.setFullscreen(nil)
        case "dragpose": companion.debugDragPose()
        case "release": companion.debugRelease()
        case "pin": companion.setPinned("Ship v0.2 today")
        case "unpin": companion.setPinned(Prefs.pinned)
        case "pomodoro": reminders.startFocus()
        case "stop": reminders.stop()
        case "settings":
            settings.show()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [settings] in
                settings.snapshot(to: YomanPaths.logDir.appendingPathComponent("settings.png"))
            }
        case "closesettings": settings.close()
        default: break
        }
    }

    private func updateMood() {
        let mood = tracker.mood()
        if mood != companion.mood, mood != .working { Memory.relieveSoon() }  // a burst of hook messages just ended
        companion.mood = mood
        moodTimer?.invalidate()
        if let wait = tracker.nextTimeout() {
            let t = Timer(timeInterval: wait + 0.05, repeats: false) { [weak self] _ in self?.updateMood() }
            RunLoop.main.add(t, forMode: .common)
            moodTimer = t
        }
    }

    /// Clears sessions whose Claude process died without a SessionEnd hook.
    private func ensureWatchdog() {
        if tracker.sessions.isEmpty {
            watchdog?.invalidate()
            watchdog = nil
            return
        }
        guard watchdog == nil else { return }
        let t = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
            guard let self else { return }
            if self.tracker.prune(isAlive: { kill($0, 0) == 0 || errno == EPERM }) > 0 { self.updateMood() }
            self.ensureWatchdog()
        }
        t.tolerance = 10
        RunLoop.main.add(t, forMode: .common)
        watchdog = t
    }

    private func bringClaudeForward() {
        let target = tracker.sessionNeedingYou() ?? tracker.latestSession()
        let id = target?.sourceBundleID ?? "com.anthropic.claudefordesktop"
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: config)
        companion.hideBubble()
    }

    // MARK: Menu bar

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let image = NSImage(systemSymbolName: "cat.fill", accessibilityDescription: "Yoman")
            ?? NSImage(systemSymbolName: "pawprint.fill", accessibilityDescription: "Yoman")
        image?.isTemplate = true
        statusItem.button?.image = image
        statusItem.button?.imagePosition = .imageLeading
        statusItem.button?.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    private func item(_ title: String, _ action: Selector?, key: String = "", on: Bool? = nil) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
        i.target = self
        if let on { i.state = on ? .on : .off }
        if action == nil { i.isEnabled = false }
        return i
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let show = item("Show Cat", #selector(toggleVisible), key: "f", on: companion.isVisible)
        show.keyEquivalentModifierMask = [.command, .option]
        menu.addItem(show)
        menu.addItem(.separator())

        // Pomodoro
        if reminders.isRunning {
            menu.addItem(item(reminders.phase == .focus ? "Pomodoro: focusing" : "Pomodoro: on a break", nil))
            menu.addItem(item("Skip to Break", #selector(startBreak)))
            menu.addItem(item("Stop Pomodoro", #selector(stopPomodoro)))
        } else {
            menu.addItem(item("Start Pomodoro (\(Prefs.focusMinutes) min)", #selector(startFocus)))
        }

        // Reminders and messages
        menu.addItem(item("Remind Me At…", #selector(remindMe)))
        if !reminders.messages.isEmpty {
            let sub = NSMenu()
            let f = DateFormatter()
            f.dateStyle = .none
            f.timeStyle = .short
            for m in reminders.messages {
                let i = NSMenuItem(title: "\(f.string(from: m.date))  \(m.text)", action: #selector(cancelMessage(_:)),
                                   keyEquivalent: "")
                i.target = self
                i.representedObject = m.id
                i.toolTip = "Click to cancel"
                sub.addItem(i)
            }
            let parent = NSMenuItem(title: "Scheduled (\(reminders.messages.count))", action: nil, keyEquivalent: "")
            parent.submenu = sub
            menu.addItem(parent)
        }
        menu.addItem(item(Prefs.pinned.isEmpty ? "Pin a Message…" : "Change Pinned Message…", #selector(pinMessage)))
        if !Prefs.pinned.isEmpty { menu.addItem(item("Clear Pinned Message", #selector(clearPinned))) }
        let test = NSMenu()
        test.addItem(item("Stretch Now", #selector(stretchNow)))
        test.addItem(item("Drink Water Now", #selector(waterNow)))
        let testParent = NSMenuItem(title: "Try a Reminder", action: nil, keyEquivalent: "")
        testParent.submenu = test
        menu.addItem(testParent)
        menu.addItem(.separator())

        // Claude Code
        let n = tracker.sessions.count
        let moodText: String = {
            switch tracker.mood() {
            case .none: return "no active session"
            case .idle: return "idle"
            case .working: return "working"
            case .needsYou: return "needs you"
            case .done: return "done"
            }
        }()
        menu.addItem(item(n == 0 ? "Claude Code: \(moodText)" : "Claude Code: \(n) session\(n == 1 ? "" : "s") · \(moodText)", nil))
        menu.addItem(item("Claude Code Hooks Installed", #selector(toggleHooks), on: HookInstaller.status(bridgePath: bridgePath)))
        if Prefs.typing && !keys.isRunning {
            menu.addItem(item("Allow Typing Reactions…", #selector(requestAccessibility)))
        }
        menu.addItem(.separator())

        menu.addItem(item("Settings…", #selector(openSettings), key: ","))
        menu.addItem(item("Launch at Login", #selector(toggleLogin), on: SMAppService.mainApp.status == .enabled))
        menu.addItem(item("Reset Position", #selector(resetPosition)))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Yoman", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    @objc private func startFocus() { reminders.startFocus() }
    @objc private func startBreak() { reminders.startBreak() }
    @objc private func stopPomodoro() { reminders.stop() }
    @objc private func stretchNow() { if !companion.isVisible { showCompanion() }; reminders.triggerStretchNow() }
    @objc private func waterNow() { if !companion.isVisible { showCompanion() }; reminders.triggerWaterNow() }
    @objc private func openSettings() { settings.show() }
    @objc private func resetPosition() { companion.resetPosition() }

    @objc private func cancelMessage(_ sender: NSMenuItem) {
        if let id = sender.representedObject as? UUID { reminders.cancel(id) }
    }

    @objc private func remindMe() {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = "Remind me"
        alert.informativeText = "The cat will meow and show your message at this time."
        let text = NSTextField(frame: NSRect(x: 0, y: 30, width: 260, height: 24))
        text.placeholderString = "e.g. Stand-up meeting"
        let picker = NSDatePicker(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        picker.datePickerStyle = .textFieldAndStepper
        picker.datePickerElements = [.hourMinute]
        picker.dateValue = Date().addingTimeInterval(30 * 60)
        let box = NSView(frame: NSRect(x: 0, y: 0, width: 260, height: 56))
        box.addSubview(text)
        box.addSubview(picker)
        alert.accessoryView = box
        alert.addButton(withTitle: "Remind Me")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = text
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let message = text.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else { return }
        // The picker only sets hour/minute; a time already past today means tomorrow.
        let cal = Calendar.current
        let hm = cal.dateComponents([.hour, .minute], from: picker.dateValue)
        var date = cal.date(bySettingHour: hm.hour ?? 0, minute: hm.minute ?? 0, second: 0, of: Date()) ?? picker.dateValue
        if date <= Date() { date = cal.date(byAdding: .day, value: 1, to: date) ?? date }
        reminders.add(message, at: date)
        let f = DateFormatter()
        f.timeStyle = .short
        companion.say("Okay! I'll remind you at \(f.string(from: date)).", for: 3)
    }

    @objc private func pinMessage() {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = "Pin a message above the cat"
        let text = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        text.stringValue = Prefs.pinned
        text.placeholderString = "e.g. Ship the release today"
        alert.accessoryView = text
        alert.addButton(withTitle: "Pin")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = text
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        Prefs.pinned = String(text.stringValue.prefix(80))
        companion.setPinned(Prefs.pinned)
    }

    @objc private func clearPinned() {
        Prefs.pinned = ""
        companion.setPinned("")
    }

    @objc private func requestAccessibility() {
        KeyListener.requestAccess()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
            NSWorkspace.shared.open(url)
        }
        updateKeyMonitor()
    }


    @objc private func toggleHooks() {
        do {
            if HookInstaller.status(bridgePath: bridgePath) {
                try HookInstaller.remove()
            } else {
                try HookInstaller.install(bridgePath: bridgePath)
                companion.say("Hooks installed. New Claude sessions will reach me.", for: 4)
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Couldn't update Claude Code settings"
            alert.informativeText = "\(error)"
            alert.runModal()
        }
    }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSLog("Yoman: login item: \(error)")
        }
    }

    private func enableLoginItemOnFirstRun() {
        guard !UserDefaults.standard.bool(forKey: Self.loginInitKey) else { return }
        UserDefaults.standard.set(true, forKey: Self.loginInitKey)
        try? SMAppService.mainApp.register()
    }
}
