import Foundation

/// Targets stale log files written by JetBrains IDEs (GoLand, DataGrip, IntelliJ, etc.)
/// under `~/Library/Logs/JetBrains/`. These are pure log artefacts — no project state,
/// no configuration — and are safe to remove without restarting the IDE.
public struct JetBrainsSafeCachesRule: ScanRule {
    public let id = "jetbrains-safe-caches"
    public let title = "JetBrains IDE Logs"
    public let reason = "Stale JetBrains IDE log file (safe to remove)"
    public let category: ScanCategory = .logsAndCrashReports
    public let riskLevel: RiskLevel = .safe
    public let confidence: Double = 0.95

    public init() {}

    public func targetDirectories(environment: ScanEnvironment) -> [URL] {
        [
            environment.homeDirectory.appending(path: "Library/Logs/JetBrains")
        ]
    }

    public func include(fileURL: URL, resourceValues: URLResourceValues) -> Bool {
        guard ScanPolicy.matchesPersonaPath(fileURL, allowedMarkers: ScanPolicy.developerSafePathMarkers) else {
            return false
        }

        // Only include recognised log file extensions
        let ext = fileURL.pathExtension.lowercased()
        let isLogFile = ext == "log" || ext == "gz" || ext == "zip" || ext.isEmpty
        guard isLogFile else { return false }

        return ScanPolicy.passesMinimumAge(
            for: resourceValues,
            minimumAgeSeconds: ScanPolicy.defaultMinimumAgeSeconds(for: category)
        )
    }
}
