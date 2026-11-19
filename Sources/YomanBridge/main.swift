import Darwin
import Foundation
import YomanCore

// yoman-bridge: tiny CLI that Claude Code runs as a hook.
//
//   yoman-bridge hook                     read hook JSON on stdin, forward a trimmed summary to the app
//   yoman-bridge hooks install|remove|status
//
// The `hook` path must never slow down or break Claude Code: it prints nothing, always exits 0,
// and gives up immediately when the app isn't running.

let args = CommandLine.arguments.dropFirst()
let env = ProcessInfo.processInfo.environment

/// Absolute path of this executable (resolving symlinks), used for the hook command.
func selfPath() -> String {
    let raw = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
    let resolved = Bundle.main.executableURL ?? raw
    return resolved.resolvingSymlinksInPath().path
}

/// Appends one line to the bridge log (kept under ~256 KB). Used to verify hooks fire from each host.
func log(_ m: BridgeMessage, delivered: Bool) {
    let fm = FileManager.default
    let url = YomanPaths.bridgeLog
    try? fm.createDirectory(at: YomanPaths.logDir, withIntermediateDirectories: true)
    if let size = try? fm.attributesOfItem(atPath: url.path)[.size] as? Int, size > 256_000 {
        try? fm.removeItem(at: url)
    }
    let stamp = ISO8601DateFormatter().string(from: Date())
    let line = "\(stamp) \(m.event) tool=\(m.tool ?? "-") session=\(m.sessionID.prefix(8)) "
        + "entry=\(m.entrypoint ?? "-") host=\(m.sourceBundleID ?? "-") delivered=\(delivered)\n"
    if let h = try? FileHandle(forWritingTo: url) {
        h.seekToEndOfFile()
        h.write(Data(line.utf8))
        try? h.close()
    } else {
        try? Data(line.utf8).write(to: url)
    }
}

func runHook() -> Never {
    let input = FileHandle.standardInput.readDataToEndOfFile()
    let grandparent: Int32? = {
        // Claude runs hooks through a shell, so the Claude process is usually our grandparent.
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.size
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getppid()]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0 else { return nil }
        let pp = info.kp_eproc.e_ppid
        return pp > 1 ? pp : nil
    }()
    if let m = BridgeMessage.from(payload: input, env: env, fallbackPID: grandparent),
       let data = try? JSONEncoder().encode(m) {
        let delivered = sendToApp(data)
        log(m, delivered: delivered)
    }
    exit(0)
}

func runHooks(_ sub: String?) -> Never {
    let bridge = selfPath()
    do {
        switch sub {
        case "install":
            let changed = try HookInstaller.install(bridgePath: bridge)
            print(changed ? "Hooks installed in \(YomanPaths.claudeSettings.path)" : "Hooks already installed")
            print("Backup: \(YomanPaths.claudeSettings.path).yoman-backup")
        case "remove":
            let changed = try HookInstaller.remove()
            print(changed ? "Hooks removed from \(YomanPaths.claudeSettings.path)" : "No Yoman hooks found")
        case "status":
            print(HookInstaller.status(bridgePath: bridge) ? "installed (\(bridge))" : "not installed")
        default:
            print("usage: yoman-bridge hooks install|remove|status")
            exit(2)
        }
    } catch {
        FileHandle.standardError.write(Data("error: \(error)\n".utf8))
        exit(1)
    }
    exit(0)
}

switch args.first {
case "hook": runHook()
case "hooks": runHooks(args.dropFirst().first)
case "debug":
    let cmd = args.dropFirst().first ?? "snapshot"
    exit(sendToApp(Data("{\"debug\":\"\(cmd)\"}".utf8)) ? 0 : 1)
default:
    print("usage: yoman-bridge hook | hooks install|remove|status")
    exit(2)
}
