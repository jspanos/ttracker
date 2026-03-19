// AuditLog.swift — Append-only timestamped audit log at ~/.ttracker/time_audit.log
import Foundation

private let auditQueue = DispatchQueue(label: "com.ttracker.auditlog", qos: .utility)

private let TIMESTAMP_FORMATTER: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd HH:mm:ss"
    f.locale = Locale(identifier: "en_US_POSIX")
    f.timeZone = TimeZone.current
    return f
}()

func auditLog(_ message: String) {
    let ts   = TIMESTAMP_FORMATTER.string(from: Date())
    let line = "\(ts)  \(message)\n"
    auditQueue.async {
        guard let data = line.data(using: .utf8) else { return }
        let path = AUDIT_LOG_PATH.path
        if FileManager.default.fileExists(atPath: path) {
            if let fh = FileHandle(forWritingAtPath: path) {
                fh.seekToEndOfFile()
                fh.write(data)
                fh.closeFile()
            }
        } else {
            try? data.write(to: AUDIT_LOG_PATH, options: .atomic)
        }
    }
}
