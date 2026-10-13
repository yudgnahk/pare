import Foundation

/// Shared "stat directory → age gate → size → mtime → finding" pipeline for
/// whole-folder cache rules.
///
/// Every rule that reports a directory as a single reclaimable unit must build
/// its finding here so the exists / minimum-age / non-empty gates cannot drift
/// between rules (they previously did: three rules shipped gate-free copies).
public enum ScanFindingBuilder {
    /// Builds a whole-folder finding for `url`.
    ///
    /// Returns `[]` when the directory is missing, was used more recently than
    /// `minimumAgeSeconds` allows (see `ScanPolicy.passesUnusedAge`), or is empty.
    public static func directoryFindings(
        at url: URL,
        category: ScanCategory,
        riskLevel: RiskLevel,
        reason: String,
        confidence: Double,
        minimumAgeSeconds: TimeInterval = ScanPolicy.reconstructibleCacheMinAgeSeconds,
        sizeIndex: DirectorySizeIndex? = nil
    ) -> [ScanFinding] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        guard ScanPolicy.passesUnusedAge(for: url, minimumAgeSeconds: minimumAgeSeconds) else {
            return []
        }

        let sized = sizeIndex?.directorySizeResult(url: url) ?? FileSystemUtils.directorySize(
            at: url, deadline: Date().addingTimeInterval(DirectorySizeIndex.defaultPerDirectoryBudgetSeconds)
        )
        // An unfinished walk is still reported ("size unknown"), never dropped as empty.
        guard sized.bytes > 0 || !sized.isComplete else { return [] }

        let lastUsed = try? url
            .resourceValues(forKeys: [.contentModificationDateKey])
            .contentModificationDate

        return [ScanFinding(
            category: category,
            riskLevel: riskLevel,
            reason: reason,
            path: url.path,
            sizeBytes: sized.bytes,
            lastUsed: lastUsed,
            confidence: confidence,
            isSizeComplete: sized.isComplete
        )]
    }
}
