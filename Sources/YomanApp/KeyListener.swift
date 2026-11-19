import AppKit
import CoreGraphics

/// Listens for key presses anywhere with a listen-only event tap (Input Monitoring permission).
/// Only the fact that a key went down is passed on; the key code and characters are never read.
final class KeyListener {
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private let onKey: () -> Void

    init(onKey: @escaping () -> Void) {
        self.onKey = onKey
    }

    /// Input Monitoring granted (or Accessibility, which also allows listen-only taps).
    static var hasAccess: Bool { CGPreflightListenEventAccess() || AXIsProcessTrusted() }

    /// Shows macOS's own prompt and adds this exact build to the Input Monitoring list.
    static func requestAccess() {
        _ = CGRequestListenEventAccess()
    }

    var isRunning: Bool { tap != nil }

    /// Returns false if the tap couldn't be created (no permission yet, or it needs a relaunch).
    @discardableResult
    func start() -> Bool {
        if tap != nil { return true }
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let me = Unmanaged<KeyListener>.fromOpaque(refcon).takeUnretainedValue()
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let t = me.tap { CGEvent.tapEnable(tap: t, enable: true) }
            } else if type == .keyDown, event.getIntegerValueField(.keyboardEventAutorepeat) == 0 {
                me.onKey()
            }
            return Unmanaged.passUnretained(event)
        }
        guard let t = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .tailAppendEventTap, options: .listenOnly,
                                        eventsOfInterest: mask, callback: callback,
                                        userInfo: Unmanaged.passUnretained(self).toOpaque())
        else { return false }
        let s = CFMachPortCreateRunLoopSource(nil, t, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), s, .commonModes)
        CGEvent.tapEnable(tap: t, enable: true)
        tap = t
        source = s
        return true
    }

    func stop() {
        if let t = tap { CGEvent.tapEnable(tap: t, enable: false) }
        if let s = source { CFRunLoopRemoveSource(CFRunLoopGetMain(), s, .commonModes) }
        tap = nil
        source = nil
    }
}
