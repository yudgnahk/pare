import Foundation

public struct LogsAndCrashReportsRule: ScanRule {
    public let id = "logs-crash-reports"
    public let title = "Logs and Crash Reports"
    public let reason = "Application log or crash report"
    public let category: ScanCategory = .logsAndCrashReports
    public let riskLevel: RiskLevel = .safe
    public let confidence: Double = 0.92

    public init() {}

    public func targetDirectories(environment: ScanEnvironment) -> [URL] {
        [
            environment.homeDirectory.appending(path: "Library/Logs"),
            environment.homeDirectory.appending(path: "Library/DiagnosticReports")
        ]
    }

    public func include(fileURL: URL, resourceValues: URLResourceValues) -> Bool {
        let ext = fileURL.pathExtension.lowercased()
        guard ["log", "crash", "ips", "diag"].contains(ext) else {
            return false
        }

        return ScanPolicy.isLowImpactPath(fileURL)
    }
}
