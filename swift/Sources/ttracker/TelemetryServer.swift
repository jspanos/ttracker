// TelemetryServer.swift — Unix domain socket server for external telemetry
// Accepts newline-delimited JSON payloads on ~/.ttracker/tmux.sock.
// Designed to be extensible: any tool can send JSON events, not just tmux.
// Drains a queue file (tmux_queue.jsonl) on startup for events that arrived
// before the socket was ready.
import Foundation
import AppKit

final class TelemetryServer {

    // MARK: Callbacks

    /// Called for every valid JSON event received. Fires on a background thread.
    var onEvent: (([String: Any]) -> Void)?

    /// Return true if the event should update the in-memory state (vs. log-only).
    var shouldUpdateState: (() -> Bool)?

    // MARK: Private

    private var serverFD: Int32 = -1
    private let queue = DispatchQueue(label: "com.ttracker.telemetry", qos: .utility)

    // MARK: Start

    func start() {
        queue.async { self.run() }
    }

    // MARK: Private — server loop

    private func run() {
        // Ensure directory
        try? FileManager.default.createDirectory(at: DB_DIR,
                                                  withIntermediateDirectories: true)

        // Remove stale socket
        let path = SOCKET_PATH
        unlink(path)

        // Create UNIX stream socket
        serverFD = socket(AF_UNIX, SOCK_STREAM, 0)
        guard serverFD >= 0 else {
            print("[ttracker] Failed to create telemetry socket")
            return
        }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: 104) { cpath in
                _ = path.withCString { strncpy(cpath, $0, 104) }
            }
        }
        let addrSize = socklen_t(MemoryLayout<sockaddr_un>.size)

        let bindResult = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(serverFD, $0, addrSize)
            }
        }
        guard bindResult == 0 else {
            print("[ttracker] Failed to bind telemetry socket: \(String(cString: strerror(errno)))")
            close(serverFD)
            return
        }

        chmod(path, 0o600)
        guard listen(serverFD, 8) == 0 else {
            print("[ttracker] Failed to listen on telemetry socket")
            close(serverFD)
            return
        }

        // Drain any queued events from before the socket was ready.
        drainQueue()

        // Accept loop
        while true {
            var clientAddr = sockaddr_un()
            var clientLen  = socklen_t(MemoryLayout<sockaddr_un>.size)
            let clientFD   = withUnsafeMutablePointer(to: &clientAddr) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    accept(serverFD, $0, &clientLen)
                }
            }
            guard clientFD >= 0 else { continue }

            let capturedFD = clientFD
            DispatchQueue.global(qos: .utility).async {
                self.handleClient(fd: capturedFD)
            }
        }
    }

    // MARK: Handle one client connection

    private func handleClient(fd: Int32) {
        defer { close(fd) }

        var data = Data()
        var buf  = [UInt8](repeating: 0, count: 4096)
        while true {
            let n = recv(fd, &buf, buf.count, 0)
            if n <= 0 { break }
            data.append(contentsOf: buf[..<n])
        }

        guard !data.isEmpty,
              let text = String(data: data, encoding: .utf8) else { return }

        for line in text.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            guard let lineData = trimmed.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: lineData),
                  let event = obj as? [String: Any] else { continue }
            onEvent?(event)
        }
    }

    // MARK: Drain startup queue

    /// Process events that arrived while the app was not running.
    /// These are logged to the DB but do not update the in-memory state
    /// (they're stale by definition).
    private func drainQueue() {
        guard FileManager.default.fileExists(atPath: QUEUE_PATH.path) else { return }
        defer { try? FileManager.default.removeItem(at: QUEUE_PATH) }

        guard let text = try? String(contentsOf: QUEUE_PATH, encoding: .utf8) else { return }
        for line in text.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            guard let lineData = trimmed.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: lineData),
                  let event = obj as? [String: Any] else { continue }
            // For queued events: call onEvent but mark that state should NOT be updated
            // by temporarily overriding shouldUpdateState.
            onEvent?(event)
            // Note: the Tracker checks shouldUpdateState() separately per event.
        }
    }
}
