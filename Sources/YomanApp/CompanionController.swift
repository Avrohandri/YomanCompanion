import AppKit
import QuartzCore
import YomanCore

/// Borderless, transparent, never-key panel that floats above normal windows on every Space
/// (including full-screen Spaces, where the cat peeks from the edge).
final class CompanionPanel: NSPanel {
    init(size: NSSize) {
        super.init(contentRect: NSRect(origin: .zero, size: size),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        hidesOnDeactivate = false
        isMovable = false
        becomesKeyOnlyIfNeeded = true
        acceptsMouseMovedEvents = true
        isReleasedWhenClosed = false
    }
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Forwards mouse input to the controller.
final class CompanionView: NSView {
    weak var controller: CompanionController?

    override var isFlipped: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    override func mouseMoved(with event: NSEvent) { controller?.cursorMoved(NSEvent.mouseLocation) }
    override func mouseDown(with event: NSEvent) { controller?.pressBegan(NSEvent.mouseLocation) }
    override func mouseDragged(with event: NSEvent) { controller?.pressDragged(NSEvent.mouseLocation) }
    override func mouseUp(with event: NSEvent) { controller?.pressEnded(NSEvent.mouseLocation) }
}

/// Owns the cat window: animation state machine, eyes, drag physics, reactions, reminders and bubbles.
final class CompanionController: NSObject {
    enum Reminder { case stretch, drink }

    // MARK: Layout

    let assets: CharacterAssets
    private var spec: CharacterSpec { assets.spec }
    private let scale: CGFloat
    private let charSize: CGSize
    private let panelSize: CGSize
    private let charOriginX: CGFloat
    /// Empty space under the cat inside the panel, so it can stretch downward while dangling.
    private let floorY: CGFloat
    /// How much the cat grows during the stretch reminder.
    private let growScale = 1.45

    let panel: CompanionPanel
    private let view: CompanionView
    private let charLayer = CALayer()
    private let spriteLayer = CALayer()
    private let pupils = [CALayer(), CALayer()]
    private let bubble = CALayer()
    private let bubbleText = CATextLayer()
    private let tag = CALayer()
    private let tagText = CATextLayer()

    // MARK: Animation state

    private(set) var currentState = ""
    private var frameIndex = 0
    private var frameTimer: Timer?
    private var oneShot: String?
    private var blinkTimer: Timer?
    private var idleTimer: Timer?
    private var bubbleTimer: Timer?
    private var stickyBubble = false

    var mood: ClaudeMood = .none { didSet { if mood != oldValue { moodChanged(from: oldValue) } } }
    var onActivateClaude: (() -> Void)?

    private(set) var sleeping = false
    /// Seconds without any mouse/keyboard input before the cat curls up (Settings → Sleep after).
    var sleepAfter: TimeInterval { TimeInterval(Prefs.sleepSeconds) }
    private var sleptAt: CFTimeInterval = 0

    // MARK: Activity reactions

    private var keyTimes: [CFTimeInterval] = []
    private var typing = false
    private var overheated = false
    private var typingTimer: Timer?
    private var lastOverheatLine: CFTimeInterval = -100

    private var paperLength: Double = 0
    private var lastScroll: CFTimeInterval = 0
    private var paperTimer: Timer?

    private var lastCursor: (p: NSPoint, t: CFTimeInterval)?
    private var reversals: [CFTimeInterval] = []
    private var lastDXSign = 0
    private var petting = false
    private var petTimer: Timer?
    private var lastPounce: CFTimeInterval = -100

    private(set) var reminder: Reminder?
    private var reminderTimer: Timer?

    private(set) var listening = false
    private(set) var peeking = false
    private var originBeforePeek: NSPoint?

    private var pinnedText = ""
    private var timerText: String?

    // MARK: Eyes / drag physics

    private var eyeShift = (dx: 0, dy: 0)
    private var lastCursorUpdate: CFTimeInterval = 0
    private var pressStart: NSPoint?
    private var originAtPress = NSPoint.zero
    private var dragging = false
    private var lastSample: (p: NSPoint, t: CFTimeInterval)?
    private var dragVelocity = CGVector.zero
    private var throwVelocity = CGVector.zero
    /// Where a pounce lands (its starting height); nil lets a throw fall to the bottom of the screen.
    private var landY: CGFloat?
    private var sx = Spring(1), sy = Spring(1), rot = Spring(0, stiffness: 120, damping: 6.5)
    /// Point (relative to the cat's bottom-center anchor, y up) that stays fixed while scaling/rotating:
    /// the grab point while dragging, so the cat hangs and stretches from where you hold it.
    private var pivot = CGPoint.zero
    private var link: CADisplayLink?
    private var lastTick: CFTimeInterval = 0

    private static let originKey = "yoman.origin"

    init(assets: CharacterAssets, scale: Int) {
        self.assets = assets
        self.scale = CGFloat(scale)
        charSize = CGSize(width: CGFloat(assets.spec.cellWidth) * self.scale,
                          height: CGFloat(assets.spec.cellHeight) * self.scale)
        panelSize = CGSize(width: max(280, charSize.width * 1.6 + 40),
                           height: charSize.height * growScale + 96 + (charSize.height * 0.35).rounded())
        charOriginX = (panelSize.width - charSize.width) / 2
        floorY = (charSize.height * 0.35).rounded()
        panel = CompanionPanel(size: panelSize)
        view = CompanionView(frame: NSRect(origin: .zero, size: panelSize))
        super.init()
        view.controller = self
        buildLayers()
        panel.contentView = view
        panel.setFrameOrigin(restoredOrigin())
        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged),
                                               name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    private func buildLayers() {
        let root = CALayer()
        view.layer = root
        view.wantsLayer = true
        let backing = NSScreen.main?.backingScaleFactor ?? 2
        let ink = CGColor(srgbRed: 0.17, green: 0.14, blue: 0.2, alpha: 1)

        charLayer.bounds = CGRect(origin: .zero, size: charSize)
        charLayer.anchorPoint = CGPoint(x: 0.5, y: 0)
        charLayer.position = CGPoint(x: panelSize.width / 2, y: floorY)
        charLayer.isGeometryFlipped = true  // sublayers use art coordinates: origin top-left
        root.addSublayer(charLayer)


        spriteLayer.frame = charLayer.bounds
        spriteLayer.magnificationFilter = .nearest
        spriteLayer.minificationFilter = .nearest
        spriteLayer.contentsGravity = .resize
        spriteLayer.contentsScale = backing
        charLayer.addSublayer(spriteLayer)

        for p in pupils {
            p.backgroundColor = assets.pupilColor
            p.actions = ["position": NSNull(), "bounds": NSNull(), "hidden": NSNull()]
            charLayer.addSublayer(p)
        }

        for (box, text, size) in [(bubble, bubbleText, CGFloat(12)), (tag, tagText, CGFloat(10.5))] {
            box.backgroundColor = CGColor(srgbRed: 1, green: 0.99, blue: 0.97, alpha: 0.97)
            box.borderColor = ink
            box.borderWidth = 2
            box.cornerRadius = size > 11 ? 8 : 6
            box.opacity = 0
            text.contentsScale = backing
            text.isWrapped = true
            text.alignmentMode = .center
            text.foregroundColor = ink
            text.font = NSFont.systemFont(ofSize: size, weight: .semibold)
            text.fontSize = size
            box.addSublayer(text)
            root.addSublayer(box)
        }
    }

    // MARK: Visibility

    var isVisible: Bool { panel.isVisible }

    func show() {
        panel.orderFrontRegardless()
        if !peeking { clampIntoScreen() }
        resumeTimers()
        play(baseState())
        layoutTag()
    }

    func hide() {
        panel.orderOut(nil)
        [frameTimer, blinkTimer, idleTimer, bubbleTimer, typingTimer, paperTimer, petTimer, reminderTimer]
            .forEach { $0?.invalidate() }
        link?.isPaused = true
        dragging = false
        typing = false
        overheated = false
        petting = false
        paperLength = 0
        reminder = nil
        sx.target = 1; sy.target = 1; sx.snap(); sy.snap()
        charLayer.removeAllAnimations()
        pivot = .zero
        charLayer.setAffineTransform(.identity)
    }

    private func resumeTimers() {
        scheduleBlink()
        checkIdle()
    }

    /// One timer aimed at the moment the idle threshold will be reached, instead of polling.
    private func scheduleIdleCheck(after seconds: TimeInterval) {
        idleTimer?.invalidate()
        guard isVisible else { return }
        let t = Timer(timeInterval: max(0.5, seconds), repeats: false) { [weak self] _ in self?.checkIdle() }
        t.tolerance = 0.3
        RunLoop.main.add(t, forMode: .common)
        idleTimer = t
    }

    // MARK: State machine

    private func baseState() -> String {
        if dragging { return "dragged" }
        if peeking { return "peek" }
        if mood == .needsYou { return "needs_you" }
        switch reminder {
        case .stretch: return "stretch"
        case .drink: return "drink"
        case nil: break
        }
        if overheated { return "overheat" }
        if typing { return "typing" }
        if petting { return "petted" }
        if paperLength >= 1 { return "paper" }
        if mood == .working { return "working" }
        if listening { return "listening" }
        return sleeping ? "sleep" : "idle"
    }

    /// Re-evaluates which state should show. One-shots (greet, done, pounce, blink) finish first unless
    /// something more important starts.
    private func refresh() {
        let base = baseState()
        if oneShot != nil, !["dragged", "needs_you", "peek", "stretch", "drink", "typing", "overheat"].contains(base) {
            return
        }
        oneShot = nil
        if currentState != base { play(base) }
    }

    func playOneShot(_ name: String) {
        guard isVisible, !dragging, !peeking, reminder == nil, spec.states[name] != nil, mood != .needsYou else { return }
        oneShot = name
        play(name)
    }

    private func play(_ name: String) {
        let name = spec.states[name] != nil ? name : "idle"
        let previous = currentState
        if !previous.isEmpty, previous != name, !["blink", "dragged"].contains(name), previous != "blink" {
            pop(name == "idle" ? 0.6 : 1)
        }
        currentState = name
        frameIndex = 0
        render()
        scheduleFrame()
    }

    private func scheduleFrame() {
        frameTimer?.invalidate()
        guard isVisible, let st = spec.states[currentState] else { return }
        if st.frames.count == 1 && st.loop { return }  // static frame: no timer at all
        let d = Double(st.durationsMs[frameIndex]) / 1000
        let t = Timer(timeInterval: d, repeats: false) { [weak self] _ in self?.advanceFrame() }
        t.tolerance = d * 0.1
        RunLoop.main.add(t, forMode: .common)
        frameTimer = t
    }

    private func advanceFrame() {
        guard let st = spec.states[currentState] else { return }
        frameIndex += 1
        if frameIndex >= st.frames.count {
            if st.loop {
                frameIndex = 0
            } else {
                oneShot = nil
                if let n = st.next, n != "idle", spec.states[n] != nil { play(n) } else { play(baseState()) }
                return
            }
        }
        render()
        scheduleFrame()
    }

    private var currentFrame: CharacterAssets.Frame? {
        guard let list = assets.frames[currentState], frameIndex < list.count else { return nil }
        return list[frameIndex]
    }

    private func render() {
        guard let frame = currentFrame else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        spriteLayer.contents = frame.image
        layoutPupils()
        CATransaction.commit()
    }

    private func layoutPupils() {
        guard let eyes = spec.eyes, let st = spec.states[currentState] else {
            pupils.forEach { $0.isHidden = true }
            return
        }
        let visible = st.eyes ?? true
        let off = st.eyeOffsets.flatMap { frameIndex < $0.count ? $0[frameIndex] : nil } ?? [0, 0]
        for (i, eye) in [eyes.left, eyes.right].enumerated() {
            let x = CGFloat(eye[0] + eyeShift.dx + off[0]) * scale
            let y = CGFloat(eye[1] + eyeShift.dy + off[1]) * scale
            pupils[i].frame = CGRect(x: x, y: y, width: CGFloat(eyes.pupil[0]) * scale, height: CGFloat(eyes.pupil[1]) * scale)
            pupils[i].isHidden = !visible
        }
    }

    private func scheduleBlink() {
        blinkTimer?.invalidate()
        let t = Timer(timeInterval: Double.random(in: 2.5...6), repeats: false) { [weak self] _ in
            guard let self else { return }
            if ["idle", "working"].contains(self.currentState), self.oneShot == nil { self.playOneShot("blink") }
            self.scheduleBlink()
        }
        t.tolerance = 0.5
        RunLoop.main.add(t, forMode: .common)
        blinkTimer = t
    }

    // MARK: Claude reactions

    private func moodChanged(from old: ClaudeMood) {
        if mood == .needsYou {
            wake(quietly: true)
        } else if old == .needsYou, stickyBubble, reminder == nil {
            hideBubble()
        }
        refresh()
    }

    func react(_ r: ClaudeReaction) {
        guard isVisible else { return }
        switch r {
        case .greet:
            wake(quietly: true)
            playOneShot("greet")
            if currentState == "greet" { hop(height: 4 * scale, duration: 0.26) }
            Sounds.play(Sounds.mrrp)
            say(Lines.sessionStart.randomElement()!, for: 3.5)
        case .finished(let project):
            wake(quietly: true)
            playOneShot("done")
            if currentState == "done" { hop(height: 11 * scale, duration: 0.42, delay: 0.09) }
            Sounds.play(Sounds.meow)
            say(Lines.finished(project: project), for: 4.5)
        case .needsYou(let project):
            Sounds.play(Sounds.meow)
            say(Lines.needsYou(project: project), sticky: true)
        }
    }

    func greetOnLaunch() {
        playOneShot("greet")
        Sounds.play(Sounds.mrrp)
        say(Lines.launch(), for: 4)
    }

    // MARK: Sleep

    private func systemIdleSeconds() -> TimeInterval {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
    }

    private func checkIdle() {
        let idle = systemIdleSeconds()
        let shouldSleep = idle >= sleepAfter && mood != .working && mood != .needsYou && reminder == nil
        if shouldSleep && !sleeping {
            sleeping = true
            sleptAt = CACurrentMediaTime()
            if !stickyBubble { hideBubble() }
            refresh()
        } else if !shouldSleep && sleeping {
            // Only grumble about being woken after a real nap, not after every short pause.
            wake(quietly: CACurrentMediaTime() - sleptAt < 60)
        }
        // Awake: check again exactly when the threshold would be crossed. Asleep: input events wake it,
        // and a slow check covers the rest.
        scheduleIdleCheck(after: sleeping ? 10 : max(1, sleepAfter - idle + 0.2))
    }

    private func wake(quietly: Bool) {
        guard sleeping else { return }
        sleeping = false
        refresh()
        scheduleIdleCheck(after: sleepAfter)
        if !quietly {
            playOneShot("greet")
            say(Lines.wake.randomElement()!, for: 3)
        }
    }

    // MARK: Typing (kneading) and overheat

    /// Called for every key press anywhere. Only the timing is used; which key was pressed is never read.
    func keyPressed() {
        guard isVisible else { return }
        let now = CACurrentMediaTime()
        keyTimes.append(now)
        keyTimes.removeAll { now - $0 > 3 }
        if sleeping { checkIdle() }
        let rate = Double(keyTimes.count) / 3
        let wasHot = overheated
        if rate >= 7 { overheated = true } else if rate < 4.5 { overheated = false }
        if overheated && !wasHot && now - lastOverheatLine > 30 {
            lastOverheatLine = now
            say(Lines.overheat.randomElement()!, for: 2.5)
        }
        let wasTyping = typing
        typing = true
        typingTimer?.invalidate()
        let t = Timer(timeInterval: 0.9, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.typing = false
            self.overheated = false
            self.refresh()
        }
        RunLoop.main.add(t, forMode: .common)
        typingTimer = t
        if !wasTyping || overheated != wasHot { refresh() }
    }

    // MARK: Scroll → paper roll

    func scrolled(dy: CGFloat, precise: Bool) {
        guard isVisible else { return }
        if sleeping { checkIdle() }
        guard Prefs.scrollPaper, spec.paper != nil, abs(dy) > 0 else { return }
        let gain = precise ? 0.06 : 1.6
        let was = paperLength
        paperLength = min(maxPaper, paperLength + Double(abs(dy)) * gain)
        lastScroll = CACurrentMediaTime()
        if was < 1, paperLength >= 1 { refresh() }
        // Trackpads send ~120 scroll events/s; the 15 Hz paper timer does the drawing.
        if paperTimer == nil {
            let t = Timer(timeInterval: 1.0 / 15, repeats: true) { [weak self] _ in self?.retractPaper() }
            RunLoop.main.add(t, forMode: .common)
            paperTimer = t
        }
    }

    /// Longest strip that still fits inside the panel, in art pixels.
    private var maxPaper: Double {
        guard let p = spec.paper else { return 0 }
        return Double(charOriginX / scale) + Double(p.x) - 2
    }

    private func retractPaper() {
        let now = CACurrentMediaTime()
        if now - lastScroll > 1.2 { paperLength = max(0, paperLength - 45.0 / 15) }
        if paperLength < 1 {
            paperLength = 0
            paperTimer?.invalidate()
            paperTimer = nil
            refresh()
        }
    }


    // MARK: Speech bubble and the small tag (pinned message / Pomodoro timer)

    private var headTop: CGFloat {
        let s = CGFloat(reminder == .stretch ? growScale : 1)
        return floorY + (charSize.height - 12 * scale) * s
    }

    func say(_ text: String, for seconds: TimeInterval = 4, sticky: Bool = false) {
        bubbleTimer?.invalidate()
        stickyBubble = sticky
        let font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        let maxW = panelSize.width - 24
        let rect = (text as NSString).boundingRect(
            with: CGSize(width: maxW - 20, height: 200), options: [.usesLineFragmentOrigin], attributes: [.font: font])
        let w = min(maxW, ceil(rect.width) + 22), h = ceil(rect.height) + 14
        let base = headTop + (tag.opacity > 0 ? tag.frame.height + 6 : 4)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        bubble.frame = CGRect(x: (panelSize.width - w) / 2, y: min(base, panelSize.height - h - 2), width: w, height: h)
        bubbleText.frame = CGRect(x: 10, y: 6, width: w - 20, height: h - 12)
        bubbleText.string = text
        CATransaction.commit()
        bubble.opacity = 1
        if !sticky {
            let t = Timer(timeInterval: seconds, repeats: false) { [weak self] _ in self?.hideBubble() }
            RunLoop.main.add(t, forMode: .common)
            bubbleTimer = t
        }
    }

    func hideBubble() {
        bubbleTimer?.invalidate()
        stickyBubble = false
        bubble.opacity = 0
    }

    func setPinned(_ text: String) {
        pinnedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        layoutTag()
    }

    func setTimerText(_ text: String?) {
        guard text != timerText else { return }
        timerText = text
        layoutTag()
    }

    private func layoutTag() {
        let parts = [timerText, pinnedText.isEmpty ? nil : pinnedText].compactMap { $0 }
        guard !parts.isEmpty else {
            tag.opacity = 0
            return
        }
        let text = parts.joined(separator: "  ·  ")
        let font = NSFont.systemFont(ofSize: 10.5, weight: .semibold)
        let maxW = panelSize.width - 30
        let rect = (text as NSString).boundingRect(
            with: CGSize(width: maxW - 14, height: 80), options: [.usesLineFragmentOrigin], attributes: [.font: font])
        let w = min(maxW, ceil(rect.width) + 16), h = ceil(rect.height) + 8
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        tag.frame = CGRect(x: (panelSize.width - w) / 2, y: headTop + 2, width: w, height: h)
        tagText.frame = CGRect(x: 7, y: 3, width: w - 14, height: h - 6)
        tagText.string = text
        tag.opacity = 1
        CATransaction.commit()
    }

    // MARK: Reminders (stretch grows the cat; drink shows the water bowl)

    func remind(_ r: Reminder) {
        guard isVisible, !dragging, !peeking else { return }
        wake(quietly: true)
        reminder = r
        oneShot = nil
        refresh()
        Sounds.play(Sounds.meow)
        reminderTimer?.invalidate()
        let t = Timer(timeInterval: r == .stretch ? 25 : 15, repeats: false) { [weak self] _ in self?.endReminder() }
        RunLoop.main.add(t, forMode: .common)
        reminderTimer = t
        if r == .stretch {
            pivot = .zero
            sx.target = growScale; sy.target = growScale
            startPhysics()
        }
        layoutTag()
        say(r == .stretch ? Lines.stretch : Lines.water, sticky: true)
    }

    func endReminder() {
        guard reminder != nil else { return }
        reminder = nil
        reminderTimer?.invalidate()
        sx.target = 1; sy.target = 1
        startPhysics()
        layoutTag()
        refresh()
        say(Lines.goodJob.randomElement()!, for: 2.5)
    }

    // MARK: Music

    /// Apple Music / Spotify started, changed track, paused or stopped.
    func setMusic(playing: Bool, newTrack: MusicWatcher.Track?) {
        let was = listening
        listening = playing && Prefs.music
        if listening, let t = newTrack, Prefs.songTitle, isVisible, !peeking, mood != .needsYou, reminder == nil {
            say(Lines.nowPlaying(t.name, t.artist), for: 4)
        }
        if listening != was {
            if listening { wake(quietly: true) }
            refresh()
        }
    }

    // MARK: Full-screen peek

    /// Pass the screen that has a full-screen app, or nil when there is none.
    func setFullscreen(_ screen: NSScreen?) {
        if let screen, Prefs.peek, isVisible {
            if !peeking {
                originBeforePeek = panel.frame.origin
                peeking = true
                if reminder != nil { endReminder() }
            }
            let f = screen.frame
            let target = NSPoint(x: f.maxX - charOriginX - charSize.width - 10,
                                 y: f.minY - floorY - CGFloat(spec.cellHeight - 62) * scale)
            panel.setFrame(NSRect(origin: target, size: panelSize), display: true, animate: true)
            oneShot = nil
            refresh()
        } else if peeking {
            peeking = false
            if let o = originBeforePeek {
                panel.setFrame(NSRect(origin: o, size: panelSize), display: true, animate: true)
            }
            originBeforePeek = nil
            refresh()
        }
    }

    // MARK: Cursor: eyes, click-through, petting, hunting

    /// Battery saver: no eye tracking, hunting or state-change pops (click-through and petting still work).
    var saver = false {
        didSet {
            guard saver != oldValue, saver else { return }
            eyeShift = (0, 0)
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layoutPupils()
            CATransaction.commit()
        }
    }

    func cursorMoved(_ p: NSPoint) {
        guard isVisible else { return }
        let now = CACurrentMediaTime()
        if now - lastCursorUpdate < 1.0 / 30 { return }
        lastCursorUpdate = now
        if sleeping { checkIdle() }
        let over = isOverCharacter(p)
        // Setting this is a WindowServer round-trip, so only touch it when it actually changes.
        if !dragging, panel.ignoresMouseEvents == over { panel.ignoresMouseEvents = !over }
        if !saver { updateEyes(toward: p) }
        if let last = lastCursor {
            let dt = now - last.t
            if dt > 0, dt < 0.5 {
                let dx = p.x - last.p.x, dy = p.y - last.p.y
                detectPetting(dx: dx, over: over && artY(p) < 44, now: now)
                if !saver { detectHunt(p, speed: hypot(dx, dy) / dt, now: now) }
            }
        }
        lastCursor = (p, now)
    }

    private func artY(_ p: NSPoint) -> CGFloat {
        (charSize.height - (p.y - panel.frame.origin.y - floorY)) / scale
    }

    private func detectPetting(dx: CGFloat, over: Bool, now: CFTimeInterval) {
        guard Prefs.petting, !dragging, mood != .needsYou, reminder == nil, !peeking else { return }
        guard over else {
            if petting { stopPetting() }
            reversals.removeAll()
            return
        }
        guard abs(dx) > 1.5 else { return }
        let sign = dx > 0 ? 1 : -1
        if sign != lastDXSign {
            if lastDXSign != 0 { reversals.append(now) }
            lastDXSign = sign
        }
        reversals.removeAll { now - $0 > 1.5 }
        if !petting, reversals.count >= 3 {
            petting = true
            wake(quietly: true)
            Sounds.play(Sounds.purr)
            say(Lines.petted.randomElement()!, for: 2)
            refresh()
        }
        if petting {
            petTimer?.invalidate()
            let t = Timer(timeInterval: 1.2, repeats: false) { [weak self] _ in self?.stopPetting() }
            RunLoop.main.add(t, forMode: .common)
            petTimer = t
        }
    }

    private func stopPetting() {
        petTimer?.invalidate()
        guard petting else { return }
        petting = false
        reversals.removeAll()
        refresh()
    }

    /// A fast cursor nearby makes the cat crouch, wiggle and pounce toward it.
    private func detectHunt(_ p: NSPoint, speed: CGFloat, now: CFTimeInterval) {
        guard Prefs.hunting, speed > 2200, now - lastPounce > 6, currentState == "idle", oneShot == nil,
              !dragging, !peeking else { return }
        let o = panel.frame.origin
        let center = NSPoint(x: o.x + panelSize.width / 2, y: o.y + floorY + charSize.height / 2)
        let dist = hypot(p.x - center.x, p.y - center.y)
        guard dist < 340, dist > charSize.width * 0.6 else { return }
        lastPounce = now
        playOneShot("pounce")
        hop(height: 13 * scale, duration: 0.4, delay: 0.4)
        Sounds.play(Sounds.mrrp)
    }

    private func updateEyes(toward p: NSPoint) {
        guard let eyes = spec.eyes else { return }
        let midX = CGFloat(eyes.left[0] + eyes.right[0] + eyes.pupil[0]) / 2
        let midY = CGFloat(eyes.left[1] + eyes.pupil[1] / 2)
        let o = panel.frame.origin
        let eye = CGPoint(x: o.x + charOriginX + midX * scale, y: o.y + floorY + charSize.height - midY * scale)
        let v = CGVector(dx: p.x - eye.x, dy: p.y - eye.y)
        let len = hypot(v.dx, v.dy)
        var shift = (dx: 0, dy: 0)
        if len > 6 * scale {
            shift.dx = Int((v.dx / len * CGFloat(eyes.range[0])).rounded())
            shift.dy = Int((-v.dy / len * CGFloat(eyes.range[1])).rounded())
        }
        if shift != eyeShift {
            eyeShift = shift
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layoutPupils()
            CATransaction.commit()
        }
    }

    /// True when the screen point is over an opaque pixel of the current frame (with a 1-pixel margin).
    private func isOverCharacter(_ p: NSPoint) -> Bool {
        let s = CGFloat(sx.value)
        let o = panel.frame.origin
        let cx = o.x + panelSize.width / 2
        let x = ((p.x - cx) / s + charSize.width / 2) / scale
        let yTop = (charSize.height - (p.y - o.y - floorY) / s) / scale
        let ix = Int(floor(x)), iy = Int(floor(yTop))
        guard ix >= -1, iy >= -1, ix <= spec.cellWidth, iy <= spec.cellHeight, let f = currentFrame else { return false }
        for dy in -1...1 { for dx in -1...1 {
            let x2 = ix + dx, y2 = iy + dy
            if x2 >= 0, y2 >= 0, x2 < spec.cellWidth, y2 < spec.cellHeight, f.mask[y2 * spec.cellWidth + x2] { return true }
        } }
        return false
    }

    // MARK: Press, drag and throw

    func pressBegan(_ p: NSPoint) {
        let o = panel.frame.origin
        pivot = CGPoint(x: max(-charSize.width / 2, min(charSize.width / 2, p.x - o.x - panelSize.width / 2)),
                        y: max(0, min(charSize.height, p.y - o.y - floorY)))
        pressStart = p
        originAtPress = panel.frame.origin
        lastSample = (p, CACurrentMediaTime())
        dragVelocity = .zero
        throwVelocity = .zero
    }

    func pressDragged(_ p: NSPoint) {
        guard let start = pressStart else { return }
        if !dragging, hypot(p.x - start.x, p.y - start.y) > 3 {
            dragging = true
            if peeking {
                peeking = false
                originBeforePeek = nil
            }
            if reminder != nil { endReminder() }
            stopPetting()
            hideBubble()
            wake(quietly: true)
            oneShot = nil
            play("dragged")
            // Lifted like mochi: it stretches down from where you hold it.
            sy.target = 1.22
            sx.target = 0.86
            sy.velocity += 3
            startPhysics()
        }
        guard dragging else { return }
        panel.setFrameOrigin(NSPoint(x: originAtPress.x + p.x - start.x, y: originAtPress.y + p.y - start.y))
        let now = CACurrentMediaTime()
        if let last = lastSample, now - last.t > 0.001 {
            let inst = CGVector(dx: (p.x - last.p.x) / (now - last.t), dy: (p.y - last.p.y) / (now - last.t))
            dragVelocity = CGVector(dx: dragVelocity.dx * 0.6 + inst.dx * 0.4, dy: dragVelocity.dy * 0.6 + inst.dy * 0.4)
        }
        lastSample = (p, now)
    }

    func pressEnded(_ p: NSPoint) {
        defer { pressStart = nil }
        guard dragging else {
            clicked()
            return
        }
        dragging = false
        let recent = lastSample.map { CACurrentMediaTime() - $0.t < 0.08 } ?? false
        let speed = hypot(dragVelocity.dx, dragVelocity.dy)
        landY = nil
        if recent, speed > 150 {
            let k = min(1, 3000 / speed)
            throwVelocity = CGVector(dx: dragVelocity.dx * k, dy: dragVelocity.dy * k)
        }
        sx.target = 1; sy.target = 1; rot.target = 0
        sy.velocity -= 4  // land with a squash
        sx.velocity += 3
        refresh()
        startPhysics()
    }

    private func clicked() {
        if reminder != nil {
            endReminder()
        } else if mood == .needsYou {
            onActivateClaude?()
        } else if peeking {
            say(Lines.peek, for: 2.5)
        } else if sleeping {
            wake(quietly: false)
        } else {
            playOneShot("greet")
            Sounds.play(Sounds.mrrp)
            say(Lines.poked.randomElement()!, for: 3)
        }
    }

    private func startPhysics() {
        if link == nil {
            let l = view.displayLink(target: self, selector: #selector(tick(_:)))
            l.add(to: .main, forMode: .common)
            link = l
        }
        lastTick = CACurrentMediaTime()
        link?.isPaused = false
    }

    @objc private func tick(_ l: CADisplayLink) {
        let now = CACurrentMediaTime()
        let dt = min(1.0 / 20, max(0.001, now - lastTick))
        lastTick = now

        if dragging {
            if let last = lastSample, now - last.t > 0.05 {
                let decay = pow(0.001, dt)
                dragVelocity = CGVector(dx: dragVelocity.dx * decay, dy: dragVelocity.dy * decay)
            }
            let vx = Double(dragVelocity.dx), vy = Double(dragVelocity.dy)
            let stretchX = min(abs(vx) / 2500, 0.22), stretchY = min(abs(vy) / 2500, 0.22)
            sx.target = 0.86 + stretchX - stretchY * 0.5
            sy.target = 1.22 + stretchY - stretchX * 0.6
            // Shaking sideways swings it like a pendulum around the grab point.
            rot.target = max(-0.45, min(0.45, vx / 2600))
        } else if throwVelocity != .zero {
            var o = panel.frame.origin
            o.x += throwVelocity.dx * dt
            o.y += throwVelocity.dy * dt
            let f = pow(0.03, dt)
            throwVelocity = CGVector(dx: throwVelocity.dx * f, dy: throwVelocity.dy * f)
            // A little gravity so pounces and throws land.
            throwVelocity.dy -= 1800 * dt
            var (clamped, hitX, hitY) = clampOrigin(o)
            if let floor = landY, clamped.y < floor {
                clamped.y = floor
                hitY = true
            }
            if hitX { throwVelocity.dx *= -0.45; sx.velocity -= 3 }
            if hitY {
                let landing = throwVelocity.dy < 0
                throwVelocity.dy *= landing ? -0.25 : -0.45
                sy.velocity -= 3
                if landing, abs(throwVelocity.dy) < 120 { throwVelocity.dy = 0 }
            }
            panel.setFrameOrigin(clamped)
            if hypot(throwVelocity.dx, throwVelocity.dy) < 15 { throwVelocity = .zero }
        }

        sx.step(dt); sy.step(dt); rot.step(dt)
        applyTransform()

        if !dragging, throwVelocity == .zero, sx.settled, sy.settled, rot.settled {
            sx.snap(); sy.snap(); rot.snap()
            if sx.value == 1, sy.value == 1 { pivot = .zero }
            applyTransform()
            l.isPaused = true
            if !peeking {
                clampIntoScreen()
                saveOrigin()
            }
        }
    }

    // MARK: Debug

    /// Freezes a mid-drag pose (grab at the head, swung right) so the pivot math can be checked in a snapshot.
    func debugDragPose() {
        pivot = CGPoint(x: 0, y: charSize.height * 0.8)
        oneShot = nil
        play("dragged")
        sx.value = 0.86; sy.value = 1.22; rot.value = 0.3
        sx.target = sx.value; sy.target = sy.value; rot.target = rot.value
        applyTransform()
    }

    func debugRelease() {
        sx.target = 1; sy.target = 1; rot.target = 0
        refresh()
        startPhysics()
    }

    /// Renders the panel's layers (no screen-recording permission needed) for visual checks.
    func snapshot(to url: URL) {
        let s = NSScreen.main?.backingScaleFactor ?? 2
        let w = Int(panelSize.width * s), h = Int(panelSize.height * s)
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let root = view.layer else { return }
        ctx.setFillColor(CGColor(srgbRed: 0.93, green: 0.95, blue: 0.98, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.interpolationQuality = .none
        ctx.scaleBy(x: s, y: s)
        root.render(in: ctx)
        guard let img = ctx.makeImage(),
              let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(dest, img, nil)
        CGImageDestinationFinalize(dest)
    }

    private func applyTransform() {
        let g = pivot
        let t = CGAffineTransform(translationX: -g.x, y: -g.y)
            .concatenating(CGAffineTransform(scaleX: sx.value, y: sy.value))
            .concatenating(CGAffineTransform(rotationAngle: rot.value))
            .concatenating(CGAffineTransform(translationX: g.x, y: g.y))
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        charLayer.setAffineTransform(t)
        CATransaction.commit()
    }

    /// A smooth vertical hop done by Core Animation (runs in the render server, so it costs the app nothing),
    /// with a squash on take-off and landing from the springs.
    private func hop(height: CGFloat, duration: CFTimeInterval, delay: CFTimeInterval = 0) {
        let a = CAKeyframeAnimation(keyPath: "position.y")
        a.isAdditive = true
        a.values = [0, height * 0.72, height, height * 0.72, 0]
        a.keyTimes = [0, 0.25, 0.5, 0.75, 1]
        a.timingFunctions = [CAMediaTimingFunction(name: .easeOut), CAMediaTimingFunction(name: .easeIn),
                             CAMediaTimingFunction(name: .easeOut), CAMediaTimingFunction(name: .easeIn)]
        a.duration = duration
        a.beginTime = CACurrentMediaTime() + delay
        a.fillMode = .backwards
        charLayer.add(a, forKey: "hop")
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.sy.velocity += 2.2
            self?.sx.velocity -= 1.6
            self?.startPhysics()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay + duration) { [weak self] in
            self?.sy.velocity -= 3.2
            self?.sx.velocity += 2.4
            self?.startPhysics()
        }
    }

    /// A tiny springy "pop" so state changes feel alive instead of snapping.
    private func pop(_ strength: Double = 1) {
        guard !dragging, isVisible, !saver else { return }
        sy.velocity += 1.3 * strength
        sx.velocity -= 0.9 * strength
        startPhysics()
    }

    // MARK: Position

    /// Keeps the cat (not the empty bubble space) on the screen it's mostly on.
    private func clampOrigin(_ o: NSPoint) -> (NSPoint, Bool, Bool) {
        let charRect = NSRect(x: o.x + charOriginX, y: o.y + floorY, width: charSize.width, height: charSize.height)
        let screen = NSScreen.screens.first { $0.visibleFrame.intersects(charRect) } ?? NSScreen.main
        guard let vf = screen?.visibleFrame else { return (o, false, false) }
        var p = o, hitX = false, hitY = false
        let minX = vf.minX - charOriginX, maxX = vf.maxX - charOriginX - charSize.width
        let minY = vf.minY - floorY, maxY = vf.maxY - charSize.height - floorY
        if p.x < minX { p.x = minX; hitX = true } else if p.x > maxX { p.x = maxX; hitX = true }
        if p.y < minY { p.y = minY; hitY = true } else if p.y > maxY { p.y = maxY; hitY = true }
        return (p, hitX, hitY)
    }

    private func clampIntoScreen() {
        panel.setFrameOrigin(clampOrigin(panel.frame.origin).0)
    }

    @objc private func screensChanged() { if !peeking { clampIntoScreen() } }

    private func restoredOrigin() -> NSPoint {
        if let a = UserDefaults.standard.array(forKey: Self.originKey) as? [Double], a.count == 2 {
            let p = NSPoint(x: a[0], y: a[1])
            let charRect = NSRect(x: p.x + charOriginX, y: p.y + floorY, width: charSize.width, height: charSize.height)
            if NSScreen.screens.contains(where: { $0.visibleFrame.intersects(charRect) }) { return p }
        }
        return defaultOrigin()
    }

    private func defaultOrigin() -> NSPoint {
        let vf = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        return NSPoint(x: vf.maxX - charOriginX - charSize.width - 16, y: vf.minY - floorY)
    }

    func resetPosition() {
        peeking = false
        originBeforePeek = nil
        panel.setFrameOrigin(defaultOrigin())
        saveOrigin()
        refresh()
    }

    private func saveOrigin() {
        let o = panel.frame.origin
        UserDefaults.standard.set([Double(o.x), Double(o.y)], forKey: Self.originKey)
    }
}
