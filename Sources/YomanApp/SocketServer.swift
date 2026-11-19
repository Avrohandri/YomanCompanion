import Darwin
import Foundation
import YomanCore

/// Listens on the Unix socket and hands each newline-terminated message to `onMessage` on the main queue.
final class SocketServer {
    enum StartError: Error { case alreadyRunning, failed(String) }

    private let path: String
    private let onMessage: (Data) -> Void
    private var listenFD: Int32 = -1
    private var acceptSource: DispatchSourceRead?
    private let io = DispatchQueue(label: "yoman.socket")

    init(path: String = YomanPaths.socket.path, onMessage: @escaping (Data) -> Void) {
        self.path = path
        self.onMessage = onMessage
    }

    func start() throws {
        try FileManager.default.createDirectory(
            at: URL(fileURLWithPath: path).deletingLastPathComponent(), withIntermediateDirectories: true)
        // A live socket means another Yoman is running; a stale file is left by a crash.
        if FileManager.default.fileExists(atPath: path) {
            if sendToApp(Data(#"{"ping":true}"#.utf8), socketPath: path) { throw StartError.alreadyRunning }
            unlink(path)
        }
        guard var addr = makeUnixAddress(path) else { throw StartError.failed("socket path too long") }
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw StartError.failed("socket() failed") }
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard bound == 0, listen(fd, 16) == 0 else {
            close(fd)
            throw StartError.failed("bind/listen failed: errno \(errno)")
        }
        chmod(path, 0o600)
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
        listenFD = fd

        let src = DispatchSource.makeReadSource(fileDescriptor: fd, queue: io)
        src.setEventHandler { [weak self] in self?.acceptAll() }
        src.resume()
        acceptSource = src
    }

    private func acceptAll() {
        while true {
            let client = accept(listenFD, nil, nil)
            if client < 0 { return }
            var noSigpipe: Int32 = 1
            setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &noSigpipe, socklen_t(MemoryLayout<Int32>.size))
            var tv = timeval(tv_sec: 0, tv_usec: 300_000)
            setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
            read(from: client)
        }
    }

    /// Messages are tiny and the client closes right after writing, so a short blocking read is fine here.
    private func read(from fd: Int32) {
        defer { close(fd) }
        var data = Data()
        var buf = [UInt8](repeating: 0, count: 4096)
        while data.count < 64 * 1024 {
            let n = Darwin.read(fd, &buf, buf.count)
            if n <= 0 { break }
            data.append(buf, count: n)
        }
        for line in data.split(separator: 0x0A) where !line.isEmpty {
            let msg = Data(line)
            DispatchQueue.main.async { self.onMessage(msg) }
        }
    }

    func stop() {
        acceptSource?.cancel()
        if listenFD >= 0 { close(listenFD) }
        unlink(path)
    }
}
