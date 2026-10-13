import Foundation

/// The parts of a `JetsamEvent-*.ips` report Pare explains: when, what was largest, and why processes were killed.
public struct JetsamEvent: Sendable, Equatable {
    public struct ResidentProcess: Sendable, Equatable {
        public let name: String
        public let residentBytes: Int64
    }

    public let date: Date?
    public let largestProcess: String?
    /// Largest resident processes first.
    public let topProcesses: [ResidentProcess]
    public let killReasons: [String]

    /// Kill causes that mean the whole system was short of memory. `per-process-limit` (one process
    /// over its own cap), `idle-exit` and `vnode-limit` do not.
    static let systemShortageKillReasons: Set<String> = [
        "highwater", "vm-pageshortage", "proc-thrashing", "fc-thrashing", "vm-compressor-thrashing",
        "vm-compressor-space-shortage", "low-swap", "sustained-memory-pressure", "vm-pageout-starvation",
        "zone-map-exhaustion",
    ]
    static let topProcessCount = 3

    public var isSystemMemoryShortage: Bool {
        killReasons.contains { Self.systemShortageKillReasons.contains($0) }
    }

    /// Parses an `.ips` report: one JSON header line, then a JSON body. Nil when the body is unusable.
    static func parse(_ report: String, defaultPageSize: Int64) -> JetsamEvent? {
        guard let newline = report.firstIndex(of: "\n"),
              let body = jsonObject(report[report.index(after: newline)...]),
              let processes = body["processes"] as? [[String: Any]] else { return nil }
        let header = jsonObject(report[..<newline]) ?? [:]
        let memoryStatus = body["memoryStatus"] as? [String: Any]
        let pageSize = int64(memoryStatus?["pageSize"]) ?? int64(body["pageSize"]) ?? defaultPageSize

        let resident = processes
            .compactMap { process -> ResidentProcess? in
                guard let name = process["name"] as? String, let pages = int64(process["rpages"]) else { return nil }
                return ResidentProcess(name: name, residentBytes: pages * pageSize)
            }
            .sorted { $0.residentBytes > $1.residentBytes }
        return JetsamEvent(
            date: date(body["date"]) ?? date(header["timestamp"]),
            largestProcess: (body["largestProcess"] as? String) ?? resident.first?.name,
            topProcesses: Array(resident.prefix(topProcessCount)),
            killReasons: processes.compactMap { $0["reason"] as? String }
        )
    }

    private static func jsonObject(_ text: Substring) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any]
    }

    private static func int64(_ value: Any?) -> Int64? {
        (value as? NSNumber)?.int64Value
    }

    /// `2026-10-07 04:47:17.10 +0700`, with or without the fractional part.
    private static func date(_ value: Any?) -> Date? {
        guard let text = value as? String else { return nil }
        for format in ["yyyy-MM-dd HH:mm:ss.SS Z", "yyyy-MM-dd HH:mm:ss Z"] {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = format
            if let date = formatter.date(from: text) { return date }
        }
        return nil
    }
}
