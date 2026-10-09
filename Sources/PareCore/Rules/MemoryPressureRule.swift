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
    /// Bounds the work: reports in the window are read newest first until this many bytes (~180 real reports).
    /// A count cap would let frequent single-app reports hide an older system-wide shortage.
    public static let maxBytesInspected: Int64 = 64 * 1024 * 1024
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
    private let inspectedBytesBudget: Int64

    /// Nil `reportDirectories` means the system and user `DiagnosticReports` folders.
    public init(
        reportDirectories: [URL]? = nil,
        swapUsedBytes: (@Sendable () async -> Int64?)? = nil,
        freeDiskBytes: (@Sendable () -> Int64?)? = nil,
        now: @escaping @Sendable () -> Date = { Date() },
        inspectedBytesBudget: Int64 = MemoryPressureRule.maxBytesInspected
    ) {
        self.reportDirectories = reportDirectories
        self.swapUsedBytes = swapUsedBytes ?? { await SwapUsageRule.currentUsedBytes() }
        self.freeDiskBytes = freeDiskBytes ?? Self.homeVolumeFreeBytes
        self.now = now
        self.inspectedBytesBudget = inspectedBytesBudget
    }

    public func targetDirectories(environment: ScanEnvironment) -> [URL] { [] }
    public func include(fileURL: URL, resourceValues: URLResourceValues) -> Bool { false }

    public func customScan(environment: ScanEnvironment) async -> [ScanFinding]? {
        let directories = reportDirectories ?? [
            URL(fileURLWithPath: "/Library/Logs/DiagnosticReports"),
            environment.homeDirectory.appending(path: "Library/Logs/DiagnosticReports"),
        ]
        let inspection = recentReports(in: directories)
        var events: [(URL, JetsamEvent)] = []
        for report in inspection.reports {
            if Task.isCancelled { return [] }
            guard let text = try? String(contentsOf: report.url, encoding: .utf8),
                  let event = Self.event(fromReport: text) else { continue }
            events.append((report.url, event.date == nil ? event.with(date: report.modified) : event))
        }
        let shortages = events.filter { $0.1.isSystemMemoryShortage }
        guard let latest = shortages.first else { return [] }
        let warning = await lowDiskWithHighSwapWarning()
        return [finding(
            for: latest.1, at: latest.0, shortageCount: shortages.count,
            isCountFloor: inspection.isTruncated, warning: warning
        )]
    }

    static func event(fromReport report: String) -> JetsamEvent? {
        JetsamEvent.parse(report, defaultPageSize: defaultPageSize)
    }

    // MARK: - Private

    private struct Report {
        let url: URL
        let modified: Date
        let bytes: Int64
    }

    /// Newest `JetsamEvent-*.ips` files within the recency window, up to `inspectedBytesBudget` in total.
    private func recentReports(in directories: [URL]) -> (reports: [Report], isTruncated: Bool) {
        let cutoff = now().addingTimeInterval(-Self.recentEventWindowSeconds)
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey]
        let reports = directories
            .flatMap { directory in
                (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: keys)) ?? []
            }
            .compactMap { url -> Report? in
                let name = url.lastPathComponent
                guard name.hasPrefix("JetsamEvent-"), name.hasSuffix(".ips"),
                      let values = try? url.resourceValues(forKeys: Set(keys)),
                      let modified = values.contentModificationDate, modified >= cutoff,
                      let size = values.fileSize, size <= Self.maxReportBytes else { return nil }
                return Report(url: url, modified: modified, bytes: Int64(size))
            }
            .sorted { $0.modified > $1.modified }
        var remaining = inspectedBytesBudget
        let within = reports.prefix { report in
            remaining -= report.bytes
            return remaining >= 0
        }
        return (Array(within), within.count < reports.count)
    }

    private func lowDiskWithHighSwapWarning() async -> String? {
        guard let swap = await swapUsedBytes(), swap > SwapUsageRule.minimumReportedSwapBytes,
              let free = freeDiskBytes(), free < Self.lowDiskWarningBytes else { return nil }
        return "Low disk space coincides with high swap use — free up disk so macOS can grow swap."
    }

    private func finding(for event: JetsamEvent, at url: URL, shortageCount: Int, isCountFloor: Bool, warning: String?) -> ScanFinding {
        let largest = event.largestProcess ?? "an unknown process"
        let largestSize = event.topProcesses.first { $0.name == largest }.map { " (\(Self.memory($0.residentBytes)))" } ?? ""
        let when = event.date.map { DateFormatter.localizedString(from: $0, dateStyle: .medium, timeStyle: .short) } ?? "a recent day"
        var sentences = ["The Mac ran out of memory on \(when); largest process was \(largest)\(largestSize)."]
        let others = event.topProcesses.filter { $0.name != largest }
        if !others.isEmpty {
            sentences.append("Other large processes: \(others.map { "\($0.name) (\(Self.memory($0.residentBytes)))" }.joined(separator: ", ")).")
        }
        if isCountFloor {
            sentences.append("At least \(shortageCount) memory \(shortageCount == 1 ? "shortage" : "shortages") in the last 7 days.")
        } else if shortageCount > 1 {
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
