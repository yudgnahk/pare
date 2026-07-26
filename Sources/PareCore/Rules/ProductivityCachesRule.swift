import Foundation

/// Cleans caches and review-category artifacts from common productivity and
/// collaboration apps: Slack, Zoom, Google Drive FS, Dropbox, Microsoft Teams,
/// OneDrive, and Office.
///
/// Safe paths (`.safe`): App caches in ~/Library/Caches/ and Application Support
/// cache subdirectories — always reconstructible on next launch.
///
/// Review paths (`.review`): Zoom cloud recordings folder (~/Documents/Zoom) —
/// 30-day age gate; user must confirm before deletion.
public struct ProductivityCachesRule: ScanRule {
    public let id = "productivity-caches"
    public let title = "Productivity App Caches"
    public let reason = "Productivity app cache (reconstructible on next launch)"
    public let category: ScanCategory = .productivityCaches
    public let riskLevel: RiskLevel = .safe
    public let confidence: Double = 0.92

    public init() {}

    public func targetDirectories(environment: ScanEnvironment) -> [URL] { [] }
    public func include(fileURL: URL, resourceValues: URLResourceValues) -> Bool { false }

    public func customScan(environment: ScanEnvironment) async -> [ScanFinding]? {
        let home = environment.homeDirectory
        var findings: [ScanFinding] = []

        // -- Safe caches (3-day age gate) --
        let safePaths: [(String, String)] = [
            ("Library/Application Support/Slack/Cache", "Slack workspace cache"),
            ("Library/Application Support/Slack/CachedData", "Slack cached data"),
            ("Library/Caches/com.tinyspeck.slackmacgap", "Slack system cache"),
            ("Library/Caches/us.zoom.xos", "Zoom cache"),
            ("Library/Caches/com.google.drivefs.finderext", "Google Drive Finder extension cache"),
            ("Library/Caches/com.dropbox.client2", "Dropbox cache"),
            ("Library/Application Support/Microsoft/Teams/Cache", "Microsoft Teams cache"),
            ("Library/Caches/com.microsoft.teams2", "Microsoft Teams system cache"),
            ("Library/Caches/com.microsoft.teams", "Microsoft Teams legacy cache"),
            ("Library/Caches/com.microsoft.OneDrive-mac", "OneDrive cache"),
            ("Library/Caches/com.microsoft.Word", "Microsoft Word cache"),
            ("Library/Caches/com.microsoft.Excel", "Microsoft Excel cache"),
            ("Library/Caches/com.microsoft.Powerpoint", "Microsoft PowerPoint cache"),
            ("Library/Caches/com.microsoft.Outlook", "Microsoft Outlook cache"),
        ]
        for (relPath, reason) in safePaths {
            findings += dirFindings(
                at: home.appending(path: relPath),
                reason: reason,
                riskLevel: .safe,
                minAgeDays: 3,
                sizeIndex: environment.sizeIndex
            )
        }

        // -- Review: Zoom cloud recordings folder (30-day age gate) --
        findings += dirFindings(
            at: home.appending(path: "Documents/Zoom"),
            reason: "Zoom cloud recordings folder",
            riskLevel: .review,
            minAgeDays: 30,
            sizeIndex: environment.sizeIndex
        )

        return findings.isEmpty ? nil : findings
    }

    // MARK: - Private

    private func dirFindings(
        at url: URL,
        reason: String,
        riskLevel: RiskLevel,
        minAgeDays: Int,
        sizeIndex: DirectorySizeIndex
    ) -> [ScanFinding] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let size = sizeIndex.directorySize(url: url)
        guard size > 0 else { return [] }

        let resourceValues = try? url.resourceValues(forKeys: [
            .contentModificationDateKey, .creationDateKey, .isDirectoryKey
        ])
        let lastUsed = resourceValues.flatMap(ScanPolicy.effectiveAgeDate(from:))

        if let date = lastUsed,
           Date().timeIntervalSince(date) < Double(minAgeDays) * 24 * 60 * 60 {
            return []
        }

        return [ScanFinding(
            category: category,
            riskLevel: riskLevel,
            reason: reason,
            path: url.path,
            sizeBytes: size,
            lastUsed: lastUsed,
            confidence: confidence
        )]
    }
}
