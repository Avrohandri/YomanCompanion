import Foundation
import IOKit.ps

/// Tells whether battery saver should be on: the setting is enabled and the Mac runs on battery or Low Power Mode.
/// Event-driven (power-source and power-state notifications), no polling.
final class PowerWatcher {
    var onChange: ((Bool) -> Void)?
    private var source: CFRunLoopSource?
    private var observer: NSObjectProtocol?
    private(set) var saving = false

    func start() {
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        if let s = IOPSNotificationCreateRunLoopSource({ ctx in
            guard let ctx else { return }
            Unmanaged<PowerWatcher>.fromOpaque(ctx).takeUnretainedValue().update()
        }, ctx)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), s, .commonModes)
            source = s
        }
        observer = NotificationCenter.default.addObserver(
            forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main) { [weak self] _ in self?.update() }
        update()
    }

    static var onBattery: Bool {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let type = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() as String?
        else { return false }
        return type == kIOPSBatteryPowerValue
    }

    /// Re-evaluates (also call when the setting changes).
    func update() {
        let now = Prefs.batterySaver && (Self.onBattery || ProcessInfo.processInfo.isLowPowerModeEnabled)
        guard now != saving else { return }
        saving = now
        DispatchQueue.main.async { self.onChange?(now) }
    }
}
