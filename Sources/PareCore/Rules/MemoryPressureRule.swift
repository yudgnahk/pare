import Foundation

/// Says when the Mac recently ran out of memory and which process was largest, from the newest
/// `JetsamEvent-*.ips` reports. Explain-only: nothing is reclaimable, and the report is never touched.
public struct MemoryPressureRule: ScanRule {
    public let id = "memory-pressure"
    public let title = "Recent Out-of-Memory Events"
    public let reason = "The Mac recently ran out of memory"
    public let category: ScanCategory = .diagnostics
    public let riskLevel: RiskLevel = .advanced
    public let confidence: Double = 0.85

    /// Only events this recent are worth mentioning.
    public static let recentEventWindowSeconds: TimeInterval = 7 * 24 * 60 * 60
    /// Bounds the work: only the newest reports in the window are read.
    public static let maxReportsInspected = 5
    /// Real reports are a few hundred KB; anything far larger is not parsed.
    public static let maxReportBytes = 8 * 1024 * 1024
    /// Apple silicon page size, used when a report omits it.
    public static let defaultPageSize: Int64 = 16_384
    /// Below this much free disk, high swap use is worth a warning: swap needs disk to grow.
    public static let lowDiskWarningBytes: Int64 = 10 * 1024 * 1024 * 1024

    private let reportDirectories: [URL]?
    private let swapUsedBytes: @Sendable () async -> Int64?
    private let freeDiskBytes: @Sendable () -> Int64?
    private let now: @Sendable () -> Date

    /// Nil `reportDirectories` means the system and user `DiagnosticReports` folders.
    public init(
        reportDirectories: [URL]? = nil,
        swapUsedBytes: (@Sendable () async -> Int64?)? = nil,
        freeDiskBytes: (@Sendable () -> Int64?)? = nil,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.reportDirectories = reportDirectories
        self.swapUsedBytes = swapUsedBytes ?? { await SwapUsageRule.currentUsedBytes() }
        self.freeDiskBytes = freeDiskBytes ?? Self.homeVolumeFreeBytes
        self.now = now
    }

    public func targetDirectories(environment: ScanEnvironment) -> [URL] { [] }
    public func include(fileURL: URL, resourceValues: URLResourceValues) -> Bool { false }

    public func customScan(environment: ScanEnvironment) async -> [ScanFinding]? {
        let directories = reportDirectories ?? [
            URL(fileURLWithPath: "/Library/Logs/DiagnosticReports"),
            environment.homeDirectory.appending(path: "Library/Logs/DiagnosticReports"),
        ]
        let events = recentReports(in: directories).compactMap { report -> (URL, JetsamEvent)? in
            guard let text = try? String(contentsOf: report.url, encoding: .utf8),
                  let event = Self.event(fromReport: text) else { return nil }
            let dated = event.date == nil ? event.with(date: report.modified) : event
            return (report.url, dated)
        }
        let shortages = events.filter { $0.1.isSystemMemoryShortage }
        guard let latest = shortages.first else { return [] }
        let warning = await lowDiskWithHighSwapWarning()
        return [finding(for: latest.1, at: latest.0, shortageCount: shortages.count, warning: warning)]
    }

    static func event(fromReport report: String) -> JetsamEvent? {
        JetsamEvent.parse(report, defaultPageSize: defaultPageSize)
    }

    // MARK: - Private

    private struct Report {
        let url: URL
        let modified: Date
    }

    /// Newest `JetsamEvent-*.ips` files within the recency window, at most `maxReportsInspected`.
    private func recentReports(in directories: [URL]) -> [Report] {
        let cutoff = now().addingTimeInterval(-Self.recentEventWindowSeconds)
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey]
        return directories
            .flatMap { directory in
                (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: keys)) ?? []
            }
            .compactMap { url -> Report? in
                let name = url.lastPathComponent
                guard name.hasPrefix("JetsamEvent-"), name.hasSuffix(".ips"),
                      let values = try? url.resourceValues(forKeys: Set(keys)),
                      let modified = values.contentModificationDate, modified >= cutoff,
                      (values.fileSize ?? 0) <= Self.maxReportBytes else { return nil }
                return Report(url: url, modified: modified)
            }
            .sorted { $0.modified > $1.modified }
            .prefix(Self.maxReportsInspected)
            .map { $0 }
    }

    private func lowDiskWithHighSwapWarning() async -> String? {
        guard let swap = await swapUsedBytes(), swap > SwapUsageRule.minimumReportedSwapBytes,
              let free = freeDiskBytes(), free < Self.lowDiskWarningBytes else { return nil }
        return "Low disk space coincides with high swap use — free up disk so macOS can grow swap."
    }

    private func finding(for event: JetsamEvent, at url: URL, shortageCount: Int, warning: String?) -> ScanFinding {
        let largest = event.largestProcess ?? "an unknown process"
        let largestSize = event.topProcesses.first { $0.name == largest }.map { " (\(Self.memory($0.residentBytes)))" } ?? ""
        let when = event.date.map { DateFormatter.localizedString(from: $0, dateStyle: .medium, timeStyle: .short) } ?? "a recent day"
        var sentences = ["The Mac ran out of memory on \(when); largest process was \(largest)\(largestSize)."]
        let others = event.topProcesses.filter { $0.name != largest }
        if !others.isEmpty {
            sentences.append("Other large processes: \(others.map { "\($0.name) (\(Self.memory($0.residentBytes)))" }.joined(separator: ", ")).")
        }
        if shortageCount > 1 {
            sentences.append("\(shortageCount) memory shortages in the last 7 days.")
        }
        if let warning { sentences.append(warning) }
        return ScanFinding(
            category: category,
            riskLevel: riskLevel,
            reason: sentences.joined(separator: " "),
            path: url.path,
            sizeBytes: 0,
            lastUsed: event.date,
            confidence: confidence,
            annotations: [.explainOnly(action: "Quit memory-heavy apps such as \(largest) before memory runs out")]
        )
    }

    private static func memory(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .memory)
    }

    private static let homeVolumeFreeBytes: @Sendable () -> Int64? = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let values = try? home.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage
    }
}

private extension JetsamEvent {
    func with(date: Date) -> JetsamEvent {
        JetsamEvent(date: date, largestProcess: largestProcess, topProcesses: topProcesses, killReasons: killReasons)
    }
}
