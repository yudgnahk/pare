import Foundation
import PareCore

/// What a multi-row "Add to Review" really stages: the distinct findings, not the selected rows.
struct DiskReviewBatchSummary: Equatable {
    /// Selected rows that resolve to at least one finding.
    let selectedItemCount: Int
    /// Distinct findings the batch adds, with findings nested inside another one dropped like the tray does.
    let findingPaths: [String]
    let totalBytes: Int64
    let reviewRiskCount: Int

    init(resolutions: [DiskReviewResolution]) {
        var selected = 0
        var byPath: [String: ScanFinding] = [:]
        for resolution in resolutions {
            let findings: [ScanFinding]
            switch resolution {
            case .covered(let covered): findings = covered
            case .insideFinding(let container): findings = [container]
            case .notCandidate, .noScan: findings = []
            }
            guard !findings.isEmpty else { continue }
            selected += 1
            findings.forEach { byPath[ScanPolicy.canonicalPathURL(URL(fileURLWithPath: $0.path)).path] = $0 }
        }
        let outermost = byPath.values.filter { finding in
            !byPath.keys.contains { Self.isStrictAncestor($0, of: finding.path) }
        }
        selectedItemCount = selected
        findingPaths = outermost.map(\.path).sorted()
        totalBytes = outermost.reduce(0) { $0 + $1.sizeBytes }
        reviewRiskCount = outermost.filter { $0.riskLevel == .review }.count
    }

    var findingCount: Int { findingPaths.count }

    /// e.g. "Add 1 finding (2.3 GB) covering 3 selected items".
    func addLabel(formatBytes: (Int64) -> String) -> String {
        let findingWord = findingCount == 1 ? "finding" : "findings"
        let itemWord = selectedItemCount == 1 ? "item" : "items"
        return "Add \(findingCount) \(findingWord) (\(formatBytes(totalBytes))) covering \(selectedItemCount) selected \(itemWord)"
    }

    /// Non-nil when the batch stages `.review`-risk findings.
    var reviewRiskWarning: String? {
        guard reviewRiskCount > 0 else { return nil }
        let findingWord = reviewRiskCount == 1 ? "finding" : "findings"
        return "Includes \(reviewRiskCount) Review-risk \(findingWord)"
    }

    private static func isStrictAncestor(_ ancestor: String, of child: String) -> Bool {
        let ancestorURL = ScanPolicy.canonicalPathURL(URL(fileURLWithPath: ancestor))
        let childURL = ScanPolicy.canonicalPathURL(URL(fileURLWithPath: child))
        return ancestorURL.pathComponents.count < childURL.pathComponents.count
            && ScanPolicy.isEqualToOrDescendant(candidate: childURL, root: ancestorURL)
    }
}
