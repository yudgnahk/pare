import Foundation
import PareCore

/// View-facing wrappers around scan results (top-level so views don't reach
/// into `ScanDashboardViewModel` for nested types).

struct SummaryItem: Identifiable, Sendable {
    let id: String
    let category: ScanCategory
    let reclaimableBytes: Int64
    let fileCount: Int
    /// Aggregated folder rows shown in the browser (not raw file count).
    let folderCount: Int

    init(summary: ScanCategorySummary, folderCount: Int = 0) {
        self.id = summary.category.rawValue
        self.category = summary.category
        self.reclaimableBytes = summary.reclaimableBytes
        self.fileCount = summary.fileCount
        self.folderCount = folderCount
    }
}

struct FindingItem: Identifiable, Sendable {
    let id: String
    let path: String
    let sizeBytes: Int64
    let category: ScanCategory
    let riskLevel: RiskLevel
    let reason: String
    let confidence: Double
    let lastUsed: Date?

    init(finding: ScanFinding) {
        self.id = "\(finding.path)-\(finding.sizeBytes)"
        self.path = finding.path
        self.sizeBytes = finding.sizeBytes
        self.category = finding.category
        self.riskLevel = finding.riskLevel
        self.reason = finding.reason
        self.confidence = finding.confidence
        self.lastUsed = finding.lastUsed
    }
}

struct CategoryLargeFiles: Identifiable, Sendable {
    let id: String
    let category: ScanCategory
    let totalBytes: Int64
    let files: [FindingItem]
}

/// Cached clean-candidate totals so confirmation sheets stop re-scanning
/// the findings array (~8 full passes per sheet render before caching).
struct CandidateStats: Equatable, Sendable {
    var safeCount = 0
    var safeBytes: Int64 = 0
    var reviewCount = 0
    var reviewBytes: Int64 = 0

    var deepCount: Int { safeCount + reviewCount }
    var deepBytes: Int64 { safeBytes + reviewBytes }

    static func compute(from findings: [ScanFinding]) -> CandidateStats {
        var stats = CandidateStats()
        for finding in findings {
            switch finding.riskLevel {
            case .safe:
                stats.safeCount += 1
                stats.safeBytes += finding.sizeBytes
            case .review:
                stats.reviewCount += 1
                stats.reviewBytes += finding.sizeBytes
            case .advanced:
                continue
            }
        }
        return stats
    }
}

enum ScanResultBuilders {
    /// Largest reclaimable findings by size, then ordered SAFE group → REVIEW group
    /// (each group still size-sorted) so both risk tiers appear when they make the cut.
    static func largestItemsSorted(from findings: [ScanFinding], limit: Int) -> [FindingItem] {
        let reclaimable = findings.filter { $0.riskLevel != .advanced }
        let top = reclaimable.sorted { $0.sizeBytes > $1.sizeBytes }.prefix(limit)
        let safe = top.filter { $0.riskLevel == .safe }
        let review = top.filter { $0.riskLevel == .review }
        return (safe + review).map(FindingItem.init(finding:))
    }

    static func makeLargeFileGroups(from findings: [ScanFinding]) -> [CategoryLargeFiles] {
        let filtered = findings.filter { ScanPolicy.isLargeFile($0.sizeBytes) }
        let grouped = Dictionary(grouping: filtered, by: \.category)

        return grouped
            .map { category, files in
                let sorted = files.sorted { $0.sizeBytes > $1.sizeBytes }
                let total = sorted.reduce(0) { $0 + $1.sizeBytes }
                return CategoryLargeFiles(
                    id: category.rawValue,
                    category: category,
                    totalBytes: total,
                    files: sorted.map(FindingItem.init(finding:))
                )
            }
            .sorted { $0.totalBytes > $1.totalBytes }
    }
}
