import Foundation
import PareCore

extension ScanDashboardViewModel {
    /// Fully prepared scan UI payload. Built off the main actor so large scans
    /// do not freeze the app at finalize (macOS “Not Responding”).
    struct PreparedScanResults: Sendable {
        let findings: [ScanFinding]
        let findingsByPath: [String: ScanFinding]
        let aggregate: FolderAggregate
        let summaries: [SummaryItem]
        let sortedTopFindings: [FindingItem]
        let toolRollups: [ToolRollup]
        /// Empty when `SmartScanFeatures.ownerView` is off.
        let ownerSections: [OwnerSection]
        /// Resolved owners, reused when an exclusion rebuilds the groups.
        let ownerByFolderPath: [String: FolderOwner]
        /// Empty when `SmartScanFeatures.ownerView` is off.
        let cleanRows: [CleanRow]
        let appIconPathByOwnerKey: [String: String]
        let candidateStats: CandidateStats
        let totalReclaimableBytes: Int64
        /// True when some reclaimable finding's size is a lower bound (sizing hit its deadline).
        let isTotalSizePartial: Bool
        /// Human-readable scan warnings (rule failures, unreadable locations — R1.2/R1.3).
        let scanWarnings: [String]
        /// Rendered paths that existed on disk at scan finish (reveal button state).
        /// Precomputed here so SwiftUI row bodies never call FileManager.
        let revealablePaths: Set<String>
        /// Rendered top-finding paths that are directories (folder icon state).
        let folderFindingPaths: Set<String>
    }

    /// Pure post-scan aggregation — safe to call from a background task. Nil `owners` keeps the legacy feed.
    nonisolated static func prepareScanResults(from report: ScanReport, owners: OwnerInputs?) -> PreparedScanResults {
        let findings = report.findings
        let base = FolderRollup.buildAggregate(from: findings)
        let resolver = owners.map { ownerResolver(for: base, inputs: $0) }
        let owned = ownerResults(aggregate: base, findings: findings, resolver: resolver)
        let aggregate = owned.aggregate
        let pathIndex = Dictionary(findings.map { ($0.path, $0) }, uniquingKeysWith: { _, last in last })
        let summaries: [SummaryItem] = report.summaries.map { summary in
            SummaryItem(
                summary: summary,
                folderCount: aggregate.rowsByCategory[summary.category]?.count ?? 0
            )
        }
        let sortedTopFindings = largestItemsSorted(from: findings, limit: 40)
        let (revealablePaths, folderFindingPaths) = revealabilityIndex(
            aggregate: aggregate,
            cleanRows: owned.cleanRows,
            topFindings: sortedTopFindings
        )
        let iconPaths = owners.map { appIconPaths(for: owned.cleanRows, index: $0.installedApps) } ?? [:]
        return PreparedScanResults(
            findings: findings,
            findingsByPath: pathIndex,
            aggregate: aggregate,
            summaries: summaries,
            sortedTopFindings: sortedTopFindings,
            toolRollups: owned.toolRollups,
            ownerSections: owned.sections,
            ownerByFolderPath: owned.ownerByFolderPath,
            cleanRows: owned.cleanRows,
            appIconPathByOwnerKey: iconPaths,
            candidateStats: CandidateStats.compute(from: findings),
            totalReclaimableBytes: report.totalReclaimableBytes,
            isTotalSizePartial: report.hasPartialSizes,
            scanWarnings: makeScanWarnings(from: report),
            revealablePaths: revealablePaths,
            folderFindingPaths: folderFindingPaths
        )
    }

    /// Builds user-facing warnings from the report's error channels (R1.2/R1.3).
    nonisolated static func makeScanWarnings(from report: ScanReport) -> [String] {
        var warnings: [String] = []
        if !report.unreadableLocations.isEmpty {
            let count = report.unreadableLocations.count
            warnings.append(
                "\(count) location\(count == 1 ? "" : "s") could not be read — grant Full Disk Access to scan everything."
            )
        }
        for failure in report.ruleFailures {
            warnings.append("\(failure.ruleTitle) failed: \(failure.message)")
        }
        for incomplete in report.incompleteRules {
            warnings.append("\(incomplete.ruleTitle): scan incomplete, results are partial. \(incomplete.message)")
        }
        return warnings
    }

    /// Stats every rendered path once, off the main actor, so row bodies can use
    /// set lookups instead of per-render FileManager calls. One stat per folder row
    /// (any owner filter can show any of them), top findings capped at 40.
    nonisolated static func revealabilityIndex(
        aggregate: FolderAggregate,
        cleanRows: [CleanRow],
        topFindings: [FindingItem]
    ) -> (revealable: Set<String>, folders: Set<String>) {
        let fm = FileManager.default
        var folderPaths = Set(aggregate.rowsByCategory.values.flatMap { $0.map(\.folderPath) })
        folderPaths.formUnion(cleanRows.map(\.record.folderPath))
        var revealable = folderPaths.filter { fm.fileExists(atPath: $0) }
        var folders: Set<String> = []
        for item in topFindings {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: item.path, isDirectory: &isDir) else { continue }
            revealable.insert(item.path)
            if isDir.boolValue {
                folders.insert(item.path)
            }
        }
        return (revealable, folders)
    }
}
