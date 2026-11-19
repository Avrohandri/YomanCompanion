import AppKit
import Combine
import SwiftUI

/// Polls the Accessibility grant while Settings is open (no SwiftUI macros: Command Line Tools lack the plugin).
final class TrustModel: ObservableObject {
    @Published var trusted = KeyListener.hasAccess
    private var timer: AnyCancellable?
    init() {
        timer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()
            .sink { [weak self] _ in self?.trusted = KeyListener.hasAccess }
    }
}

struct SettingsView: View {
    @AppStorage(Prefs.Key.name) private var name = "Jagoan"
    @AppStorage(Prefs.Key.size) private var size = 2
    @AppStorage(Prefs.Key.sounds) private var sounds = true
    @AppStorage(Prefs.Key.typing) private var typing = true
    @AppStorage(Prefs.Key.scrollPaper) private var scrollPaper = true
    @AppStorage(Prefs.Key.hunting) private var hunting = true
    @AppStorage(Prefs.Key.petting) private var petting = true
    @AppStorage(Prefs.Key.stretchOn) private var stretchOn = true
    @AppStorage(Prefs.Key.stretchMinutes) private var stretchMinutes = 50
    @AppStorage(Prefs.Key.waterOn) private var waterOn = true
    @AppStorage(Prefs.Key.waterMinutes) private var waterMinutes = 60
    @AppStorage(Prefs.Key.peek) private var peek = true
    @AppStorage(Prefs.Key.music) private var music = true
    @AppStorage(Prefs.Key.songTitle) private var songTitle = true
    @AppStorage(Prefs.Key.sleepSeconds) private var sleepSeconds = 15
    @AppStorage(Prefs.Key.focusMinutes) private var focusMinutes = 25
    @AppStorage(Prefs.Key.breakMinutes) private var breakMinutes = 5
    @AppStorage(Prefs.Key.longBreakMinutes) private var longBreakMinutes = 15

    @ObservedObject var trust: TrustModel

    var body: some View {
        Form {
            Section("You") {
                TextField("Your name", text: $name)
                Picker("Cat size", selection: $size) {
                    Text("Small").tag(1)
                    Text("Medium").tag(2)
                    Text("Large").tag(3)
                }
                .pickerStyle(.segmented)
                Stepper("Sleep after \(sleepSeconds) s without input", value: $sleepSeconds, in: 5...600, step: 5)
            }
            Section("Reactions") {
                Toggle("Sounds (meow, purr)", isOn: $sounds)
                Toggle("Knead while I type", isOn: $typing)
                if typing && !trust.trusted {
                    HStack {
                        Text("Needs Input Monitoring permission. Only the timing of key presses is used, never which keys.")
                            .font(.caption).foregroundStyle(.secondary)
                        Button("Grant…") { requestAccessibility() }
                    }
                }
                Toggle("Unroll paper when I scroll", isOn: $scrollPaper)
                Toggle("Hunt fast cursors", isOn: $hunting)
                Toggle("Purr when petted (wiggle the cursor over its head)", isOn: $petting)
                Toggle("Peek from the screen edge in full screen", isOn: $peek)
                Toggle("Vibe to Apple Music / Spotify", isOn: $music)
                Toggle("Show the song title when a track starts", isOn: $songTitle)
                    .disabled(!music)
            }
            Section("Reminders") {
                Toggle("Stretch reminder", isOn: $stretchOn)
                Stepper("Every \(stretchMinutes) minutes", value: $stretchMinutes, in: 10...180, step: 5)
                    .disabled(!stretchOn)
                Toggle("Drink water reminder", isOn: $waterOn)
                Stepper("Every \(waterMinutes) minutes", value: $waterMinutes, in: 10...180, step: 5)
                    .disabled(!waterOn)
            }
            Section("Pomodoro") {
                Stepper("Focus: \(focusMinutes) min", value: $focusMinutes, in: 5...90, step: 5)
                Stepper("Break: \(breakMinutes) min", value: $breakMinutes, in: 1...30)
                Stepper("Long break (every 4th): \(longBreakMinutes) min", value: $longBreakMinutes, in: 5...60, step: 5)
            }
        }
        .formStyle(.grouped)
        .frame(width: 440, height: 600)
    }

    private func requestAccessibility() {
        KeyListener.requestAccess()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
            NSWorkspace.shared.open(url)
        }
    }

}

/// Hosts SettingsView in a normal window (the app itself has no Dock icon).
final class SettingsWindowController {
    private var window: NSWindow?

    func show() {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: 600),
                             styleMask: [.titled, .closable], backing: .buffered, defer: false)
            w.title = "Yoman Settings"
            w.contentView = NSHostingView(rootView: SettingsView(trust: TrustModel()))
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}
