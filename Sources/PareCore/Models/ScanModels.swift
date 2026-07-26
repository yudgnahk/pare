import Foundation

public enum ScanCategory: String, CaseIterable, Sendable {
    case userCaches = "User Caches"
    case temporaryFiles = "Temporary Files"
    case logsAndCrashReports = "Logs and Crash Reports"
    case browserCaches = "Browser Caches"
    case developerBuildArtifacts = "Developer Build Artifacts"
    case developerPackageCaches = "Developer Package Caches"
    case developerSimulatorCaches = "Developer Simulator Caches"
    case designerCaches = "Designer Caches"
    case videoBuilderCaches = "Video Builder Caches"
    case aiToolCaches = "AI Tool Caches"
    case installerFiles = "Installer Files"
    case applications = "Applications"
    case projectArtifacts = "Project Artifacts"
    case deviceBackups = "Device Backups"
    case productivityCaches = "Productivity Caches"
    case launchAgents = "Launch Agents"
}

public enum RiskLevel: String, Sendable {
    case safe
    case review
    case advanced
}

public struct ScannedFile: Sendable {
    public let url: URL
    public let sizeBytes: Int64
    public let lastModified: Date?

    public init(url: URL, sizeBytes: Int64, lastModified: Date?) {
        self.url = url
        self.sizeBytes = sizeBytes
        self.lastModified = lastModified
    }
}

public struct ScanFinding: Sendable {
    public let category: ScanCategory
    public let riskLevel: RiskLevel
    /// Human-readable reason this file was flagged (copied from the matching `ScanRule`).
    public let reason: String
    public let path: String
    public let sizeBytes: Int64
    public let lastUsed: Date?
    public let confidence: Double

    public init(
        category: ScanCategory,
        riskLevel: RiskLevel,
        reason: String,
        path: String,
        sizeBytes: Int64,
        lastUsed: Date?,
        confidence: Double
    ) {
        self.category = category
        self.riskLevel = riskLevel
        self.reason = reason
        self.path = path
        self.sizeBytes = sizeBytes
        self.lastUsed = lastUsed
        self.confidence = confidence
    }
}

public struct ScanCategorySummary: Sendable {
    public let category: ScanCategory
    public let reclaimableBytes: Int64
    public let fileCount: Int

    public init(category: ScanCategory, reclaimableBytes: Int64, fileCount: Int) {
        self.category = category
        self.reclaimableBytes = reclaimableBytes
        self.fileCount = fileCount
    }
}

/// A rule whose scan threw — "rule failed" is not "rule found nothing" (R1.2).
public struct ScanRuleFailure: Sendable {
    public let ruleID: String
    public let ruleTitle: String
    public let message: String

    public init(ruleID: String, ruleTitle: String, message: String) {
        self.ruleID = ruleID
        self.ruleTitle = ruleTitle
        self.message = message
    }
}

public struct ScanReport: Sendable {
    public let findings: [ScanFinding]
    public let summaries: [ScanCategorySummary]
    /// Rules that failed during this scan (R1.2). Empty on a fully clean run.
    public let ruleFailures: [ScanRuleFailure]
    /// Distinct locations the traversal could not read — permission gaps,
    /// typically missing Full Disk Access (R1.3). Sorted for stable display.
    public let unreadableLocations: [String]

    public init(
        findings: [ScanFinding],
        summaries: [ScanCategorySummary],
        ruleFailures: [ScanRuleFailure] = [],
        unreadableLocations: [String] = []
    ) {
        self.findings = findings
        self.summaries = summaries
        self.ruleFailures = ruleFailures
        self.unreadableLocations = unreadableLocations
    }

    /// Sum of category reclaimable totals. Excludes `.advanced` findings (detect-only);
    /// those remain in `findings` but are not counted as reclaimable by `ScanRunner`.
    public var totalReclaimableBytes: Int64 {
        summaries.reduce(0) { $0 + $1.reclaimableBytes }
    }
}
