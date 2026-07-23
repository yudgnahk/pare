import Foundation

/// Category totals included in a diagnostics export (no file paths).
public struct DiagnosticsCategorySummary: Codable, Sendable, Equatable {
    public let category: String
    public let reclaimableBytes: Int64
    public let fileCount: Int

    public init(category: String, reclaimableBytes: Int64, fileCount: Int) {
        self.category = category
        self.reclaimableBytes = reclaimableBytes
        self.fileCount = fileCount
    }
}

/// Risk-level counts for the last scan (paths never included).
public struct DiagnosticsRiskCounts: Codable, Sendable, Equatable {
    public let safe: Int
    public let review: Int
    public let advanced: Int

    public init(safe: Int, review: Int, advanced: Int) {
        self.safe = safe
        self.review = review
        self.advanced = advanced
    }

    public var total: Int { safe + review + advanced }
}

/// Support-safe JSON payload for bug reports. Never embeds full absolute user paths.
public struct DiagnosticsBundle: Codable, Sendable, Equatable {
    public let schemaVersion: Int
    public let appVersion: String
    public let macOSVersion: String
    public let exportDate: Date
    public let scanDate: Date?
    public let scanDurationSeconds: Double?
    /// `"all"` for the unified app scan; CLI may pass a profile name.
    public let profileUsed: String
    public let totalReclaimableBytes: Int64
    public let findingCount: Int
    public let categorySummaries: [DiagnosticsCategorySummary]
    public let riskCounts: DiagnosticsRiskCounts
    public let ruleIds: [String]
    /// Anonymized directory prefixes only (e.g. `~/Library/Caches`), never full paths.
    public let anonymizedPathPrefixes: [String]

    public init(
        schemaVersion: Int = 1,
        appVersion: String,
        macOSVersion: String,
        exportDate: Date = Date(),
        scanDate: Date?,
        scanDurationSeconds: Double?,
        profileUsed: String,
        totalReclaimableBytes: Int64,
        findingCount: Int,
        categorySummaries: [DiagnosticsCategorySummary],
        riskCounts: DiagnosticsRiskCounts,
        ruleIds: [String],
        anonymizedPathPrefixes: [String]
    ) {
        self.schemaVersion = schemaVersion
        self.appVersion = appVersion
        self.macOSVersion = macOSVersion
        self.exportDate = exportDate
        self.scanDate = scanDate
        self.scanDurationSeconds = scanDurationSeconds
        self.profileUsed = profileUsed
        self.totalReclaimableBytes = totalReclaimableBytes
        self.findingCount = findingCount
        self.categorySummaries = categorySummaries
        self.riskCounts = riskCounts
        self.ruleIds = ruleIds
        self.anonymizedPathPrefixes = anonymizedPathPrefixes
    }
}

/// Builds support diagnostics JSON without leaking absolute paths or personal file names.
public enum DiagnosticsExporter {
    public static let schemaVersion = 1

    /// Build a bundle from an optional last scan report.
    ///
    /// - Parameters:
    ///   - report: Last scan results; pass `nil` if the user has not scanned yet.
    ///   - profileUsed: Profile or `"all"` for the unified app catalog.
    ///   - scanDate / scanDurationSeconds: Optional timing metadata from the UI.
    ///   - appVersion: Marketing version (e.g. from Info.plist).
    ///   - macOSVersion: Host OS product version string.
    ///   - ruleIds: Registered rule ids for the scan that was (or would be) run.
    ///   - homeDirectory: Used only to anonymize sample path prefixes.
    ///   - pathSamples: Optional finding paths used solely to derive anonymized prefixes.
    public static func makeBundle(
        report: ScanReport?,
        profileUsed: String,
        scanDate: Date? = nil,
        scanDurationSeconds: Double? = nil,
        appVersion: String = currentAppVersion(),
        macOSVersion: String = currentMacOSVersion(),
        ruleIds: [String] = RuleCatalog.all.map(\.id).sorted(),
        homeDirectory: String = FileManager.default.homeDirectoryForCurrentUser.path,
        pathSamples: [String] = [],
        exportDate: Date = Date()
    ) -> DiagnosticsBundle {
        let summaries: [DiagnosticsCategorySummary]
        let reclaimable: Int64
        let findingCount: Int
        let risks: DiagnosticsRiskCounts
        let samples: [String]

        if let report {
            summaries = report.summaries.map {
                DiagnosticsCategorySummary(
                    category: $0.category.rawValue,
                    reclaimableBytes: $0.reclaimableBytes,
                    fileCount: $0.fileCount
                )
            }
            reclaimable = report.totalReclaimableBytes
            findingCount = report.findings.count
            risks = riskCounts(from: report.findings)
            samples = pathSamples.isEmpty ? report.findings.map(\.path) : pathSamples
        } else {
            summaries = []
            reclaimable = 0
            findingCount = 0
            risks = DiagnosticsRiskCounts(safe: 0, review: 0, advanced: 0)
            samples = pathSamples
        }

        return DiagnosticsBundle(
            schemaVersion: schemaVersion,
            appVersion: appVersion,
            macOSVersion: macOSVersion,
            exportDate: exportDate,
            scanDate: scanDate,
            scanDurationSeconds: scanDurationSeconds,
            profileUsed: profileUsed,
            totalReclaimableBytes: reclaimable,
            findingCount: findingCount,
            categorySummaries: summaries,
            riskCounts: risks,
            ruleIds: ruleIds,
            anonymizedPathPrefixes: anonymizedPathPrefixes(
                from: samples,
                homeDirectory: homeDirectory
            )
        )
    }

    /// Convenience when the app already has category rollups but not a full `ScanReport`.
    public static func makeBundle(
        categorySummaries: [DiagnosticsCategorySummary],
        riskCounts: DiagnosticsRiskCounts,
        profileUsed: String,
        totalReclaimableBytes: Int64,
        findingCount: Int,
        scanDate: Date?,
        scanDurationSeconds: Double?,
        pathSamples: [String] = [],
        appVersion: String = currentAppVersion(),
        macOSVersion: String = currentMacOSVersion(),
        ruleIds: [String] = RuleCatalog.all.map(\.id).sorted(),
        homeDirectory: String = FileManager.default.homeDirectoryForCurrentUser.path,
        exportDate: Date = Date()
    ) -> DiagnosticsBundle {
        DiagnosticsBundle(
            schemaVersion: schemaVersion,
            appVersion: appVersion,
            macOSVersion: macOSVersion,
            exportDate: exportDate,
            scanDate: scanDate,
            scanDurationSeconds: scanDurationSeconds,
            profileUsed: profileUsed,
            totalReclaimableBytes: totalReclaimableBytes,
            findingCount: findingCount,
            categorySummaries: categorySummaries,
            riskCounts: riskCounts,
            ruleIds: ruleIds,
            anonymizedPathPrefixes: anonymizedPathPrefixes(
                from: pathSamples,
                homeDirectory: homeDirectory
            )
        )
    }

    /// Pretty-printed JSON suitable for attaching to a GitHub issue.
    public static func jsonData(from bundle: DiagnosticsBundle) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(bundle)
    }

    /// Replace the home directory with `~` and other `/Users/<name>` with `/Users/<user>`.
    public static func anonymizePath(
        _ path: String,
        homeDirectory: String = FileManager.default.homeDirectoryForCurrentUser.path
    ) -> String {
        let normalizedHome = homeDirectory.hasSuffix("/")
            ? String(homeDirectory.dropLast())
            : homeDirectory

        if path == normalizedHome {
            return "~"
        }
        if path.hasPrefix(normalizedHome + "/") {
            return "~" + path.dropFirst(normalizedHome.count)
        }

        // Other users' homes: /Users/alice/Library/... → /Users/<user>/Library/...
        if path.hasPrefix("/Users/") {
            let rest = path.dropFirst("/Users/".count)
            if let slash = rest.firstIndex(of: "/") {
                let remainder = rest[slash...]
                return "/Users/<user>" + remainder
            }
            return "/Users/<user>"
        }

        return path
    }

    /// Directory-level prefixes only (depth capped) so support sees *where*, not *what files*.
    public static func anonymizedPathPrefixes(
        from paths: [String],
        homeDirectory: String = FileManager.default.homeDirectoryForCurrentUser.path,
        maxDepth: Int = 4,
        limit: Int = 24
    ) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        result.reserveCapacity(min(limit, paths.count))

        for path in paths {
            let anonymized = anonymizePath(path, homeDirectory: homeDirectory)
            let prefix = pathPrefix(anonymized, maxDepth: maxDepth)
            guard !prefix.isEmpty, seen.insert(prefix).inserted else { continue }
            result.append(prefix)
            if result.count >= limit { break }
        }
        return result.sorted()
    }

    public static func currentAppVersion() -> String {
        let bundle = Bundle.main
        let short = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        switch (short, build) {
        case let (s?, b?) where !s.isEmpty && !b.isEmpty && s != b:
            return "\(s) (\(b))"
        case let (s?, _) where !s.isEmpty:
            return s
        case let (_, b?) where !b.isEmpty:
            return b
        default:
            return "unknown"
        }
    }

    public static func currentMacOSVersion() -> String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    }

    // MARK: - Private

    private static func riskCounts(from findings: [ScanFinding]) -> DiagnosticsRiskCounts {
        var safe = 0
        var review = 0
        var advanced = 0
        for finding in findings {
            switch finding.riskLevel {
            case .safe: safe += 1
            case .review: review += 1
            case .advanced: advanced += 1
            }
        }
        return DiagnosticsRiskCounts(safe: safe, review: review, advanced: advanced)
    }

    /// Keep leading path components only: `~/Library/Caches/foo/bar` → `~/Library/Caches/foo`
    /// when maxDepth is 4 (`~` counts as one component for tilde paths).
    private static func pathPrefix(_ path: String, maxDepth: Int) -> String {
        guard maxDepth > 0 else { return "" }
        if path == "~" { return "~" }

        let isTilde = path.hasPrefix("~/")
        let trimmed = isTilde ? String(path.dropFirst(2)) : path
        let parts = trimmed.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard !parts.isEmpty else { return isTilde ? "~" : "" }

        // For `~/…`, budget includes the `~` component.
        let take = isTilde ? max(0, maxDepth - 1) : maxDepth
        let kept = Array(parts.prefix(take))
        if isTilde {
            return "~/" + kept.joined(separator: "/")
        }
        if path.hasPrefix("/") {
            return "/" + kept.joined(separator: "/")
        }
        return kept.joined(separator: "/")
    }
}
