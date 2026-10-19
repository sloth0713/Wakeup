import Foundation
import os

enum WakeLog {
    static let filterKey = "WakeRelay"
    private static let gate = NSLock()
    private static let logger = Logger(subsystem: "com.demo.WakeApp", category: "WakeRelay")
    private static let stamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "MM-dd HH:mm:ss"
        return formatter
    }()

    static func appendLine(_ text: String) {
        let line = lockedStamp(text)
        writeLine(line)
        logger.notice("[\(Self.filterKey, privacy: .public)] \(text, privacy: .public)")
        DispatchQueue.main.async {
            WakeRelay.shared.reloadLines()
        }
    }

    static func readLines() -> [String] {
        gate.lock()
        defer { gate.unlock() }
        guard let path = logPath() else { return [] }
        guard let text = try? String(contentsOf: path, encoding: .utf8) else { return [] }
        return text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
    }

    static func clear() {
        gate.lock()
        defer { gate.unlock() }
        guard let path = logPath() else { return }
        try? FileManager.default.removeItem(at: path)
    }

    private static func lockedStamp(_ text: String) -> String {
        gate.lock()
        defer { gate.unlock() }
        return "[\(stamp.string(from: Date()))] [\(filterKey)] \(text)\n"
    }

    private static func writeLine(_ line: String) {
        gate.lock()
        defer { gate.unlock() }
        guard let path = logPath() else { return }
        guard let raw = line.data(using: .utf8) else { return }
        if FileManager.default.fileExists(atPath: path.path) {
            guard let handle = try? FileHandle(forWritingTo: path) else { return }
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: raw)
            try? handle.synchronize()
        } else {
            try? raw.write(to: path, options: .atomic)
        }
    }

    private static func logPath() -> URL? {
        FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("wake-log.txt")
    }
}
