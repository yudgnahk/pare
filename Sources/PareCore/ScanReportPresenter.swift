import Foundation

/// Presentation helpers shared by the CLI and the app's view models.
///
/// One home for the report-shaping logic that was previously duplicated:
/// largest-items ordering, large-file category groups, byte formatting
/// (consistent units, KB through TB), and risk tags.
public enum ScanReportPresenter {
    /// Large findings for one category, SAFE first then REVIEW, each size-sorted.
    public struct LargeFileGroup: Sendable {
        public let category: ScanCategory
        public let totalBytes: Int64
        public let files: [ScanFinding]
    }

    /// Top-N reclaimable findings by size, then display order SAFE group →
    /// REVIEW group (each still size-sorted) so both risk tiers appear when
    /// they make the cut. ADVANCED findings are never included.
    public static func largestItems(from findings: [ScanFinding], limit: Int) -> [ScanFinding] {
        let reclaimable = findings.filter { $0.riskLevel != .advanced }
        let top = reclaimable.sorted { $0.sizeBytes > $1.sizeBytes }.prefix(limit)
        let safe = top.filter { $0.riskLevel == .safe }
        let review = top.filter { $0.riskLevel == .review }
        return Array(safe + review)
    }

    /// Findings over `ScanPolicy.largeFileThresholdBytes`, grouped by category
    /// (largest category first). Within each group: SAFE first, then REVIEW,
    /// each by size.
    public static func largeFileGroups(from findings: [ScanFinding]) -> [LargeFileGroup] {
        let largeFindings = findings.filter { ScanPolicy.isLargeFile($0.sizeBytes) }
        let grouped = Dictionary(grouping: largeFindings, by: \.category)

        return grouped
            .map { category, files in
                let safe = files.filter { $0.riskLevel == .safe }.sorted { $0.sizeBytes > $1.sizeBytes }
                let review = files.filter { $0.riskLevel == .review }.sorted { $0.sizeBytes > $1.sizeBytes }
                let sortedFiles = safe + review
                let totalBytes = sortedFiles.reduce(0) { $0 + $1.sizeBytes }
                return LargeFileGroup(category: category, totalBytes: totalBytes, files: sortedFiles)
            }
            .sorted { $0.totalBytes > $1.totalBytes }
    }

    /// Formats byte counts with consistent units (KB/MB/GB/TB, file style).
    public static func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    /// Bracketed risk tag for terminal/report output, e.g. `[SAFE]`.
    public static func riskTag(_ level: RiskLevel) -> String {
        switch level {
        case .safe:     return "[SAFE]"
        case .review:   return "[REVIEW]"
        case .advanced: return "[ADVANCED]"
        }
    }
}
