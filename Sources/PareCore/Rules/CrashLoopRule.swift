import Foundation

/// Explain-only: an app whose crash reports pile up inside a short window is crash-looping.
/// One finding per app on a virtual path, so it never aliases a report `LogsAndCrashReportsRule` lists for deletion.
public struct CrashLoopRule: ScanRule {
    public let id = "crash-loops"
    public let title = "Crash Loops"
    public let reason = "App crashing repeatedly (explain only)"
    public let category: ScanCategory = .logsAndCrashReports
    public let riskLevel: RiskLevel = .advanced
    public let confidence: Double = 0.9

    /// Reports inside one `window` that count as a crash loop.
    public static let minimumReports = 10
    public static let window: TimeInterval = 2 * 24 * 60 * 60
    /// Older reports are history, not an ongoing loop.
    public static let lookback: TimeInterval = 30 * 24 * 60 * 60

    static let reportExtensions: Set<String> = ["ips", "crash"]
    /// Enough for the one-line `.ips` JSON header.
    private static let headerReadLimit = 16 * 1024

    private let now: @Sendable () -> Date

    public init(now: @escaping @Sendable () -> Date = { Date() }) {
        self.now = now
    }

    public func targetDirectories(environment: ScanEnvironment) -> [URL] { [] }
    public func include(fileURL: URL, resourceValues: URLResourceValues) -> Bool { false }

    public func customScan(environment: ScanEnvironment) async -> [ScanFinding]? {
        let home = environment.homeDirectory
        let primary = home.appending(path: "Library/Logs/DiagnosticReports")
        let directories = [primary, home.appending(path: "Library/DiagnosticReports")]
        let cutoff = now().addingTimeInterval(-Self.lookback)
        let reports = directories.flatMap(Self.crashReports).filter { $0.date >= cutoff }

        return Dictionary(grouping: reports, by: \.app)
            .sorted { $0.key < $1.key }
            .compactMap { app, reports in finding(app: app, reports: reports, directory: primary) }
    }

    // MARK: - Grouping

    struct CrashReport {
        let app: String
        let date: Date
        let bytes: Int64
    }

    private func finding(app: String, reports: [CrashReport], directory: URL) -> ScanFinding? {
        let dates = reports.map(\.date).sorted()
        let peak = Self.densestWindowCount(dates)
        guard peak >= Self.minimumReports else { return nil }
        let days = Int(Self.window / (24 * 60 * 60))
        let safeName = app.replacingOccurrences(of: "/", with: ":")
        return ScanFinding(
            category: category,
            riskLevel: riskLevel,
            reason: "\(app) crashed \(peak)× in \(days) days. Update or reinstall it, or report the crash to "
                + "its developer; Pare only explains this, and the reports themselves are listed separately.",
            path: directory.appending(path: "\(safeName) (crash loop)").path,
            sizeBytes: reports.reduce(0) { $0 + $1.bytes },
            lastUsed: dates.last,
            confidence: confidence
        )
    }

    /// Largest number of sorted dates that fit inside one `window`.
    static func densestWindowCount(_ sorted: [Date]) -> Int {
        var best = 0
        var start = 0
        for end in sorted.indices {
            while sorted[end].timeIntervalSince(sorted[start]) > window { start += 1 }
            best = max(best, end - start + 1)
        }
        return best
    }

    // MARK: - Parsing

    private static func crashReports(in directory: URL) -> [CrashReport] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .isSymbolicLinkKey, .contentModificationDateKey, .fileSizeKey]
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]
        ) else { return [] }
        let formatter = timestampFormatter()
        return entries.compactMap { (url: URL) -> CrashReport? in
            guard reportExtensions.contains(url.pathExtension.lowercased()),
                  let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true, values.isSymbolicLink != true else { return nil }
            let header = headerFields(of: url)
            let app = header?.app ?? appName(fromFileName: url.lastPathComponent)
            let stamped = header?.timestamp.flatMap { formatter.date(from: $0) }
            guard let date = stamped ?? values.contentModificationDate else { return nil }
            return CrashReport(app: app, date: date, bytes: Int64(values.fileSize ?? 0))
        }
    }

    /// `app_name` (else `name`) and `timestamp` from the one-line JSON header of an `.ips` report.
    static func headerFields(of url: URL) -> (app: String, timestamp: String?)? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: headerReadLimit),
              let firstLine = data.split(separator: UInt8(ascii: "\n"), maxSplits: 1).first,
              let object = try? JSONSerialization.jsonObject(with: Data(firstLine)) as? [String: Any] else {
            return nil
        }
        let app = (object["app_name"] as? String) ?? (object["name"] as? String)
        guard let app, !app.isEmpty else { return nil }
        return (app, object["timestamp"] as? String)
    }

    /// `Foo Helper-2026-10-05-101112.ips` or `Foo Helper_2026-10-05-…` → `Foo Helper`.
    static func appName(fromFileName name: String) -> String {
        let stem = (name as NSString).deletingPathExtension
        guard let range = stem.range(of: #"[-_]\d{4}-\d{2}-\d{2}"#, options: .regularExpression),
              range.lowerBound > stem.startIndex else { return stem }
        return String(stem[..<range.lowerBound])
    }

    private static func timestampFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SS Z"
        return formatter
    }
}
