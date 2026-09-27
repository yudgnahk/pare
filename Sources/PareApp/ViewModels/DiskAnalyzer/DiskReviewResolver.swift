import Foundation
import PareCore

/// Outcome of checking whether a Disk Analyzer entry may enter the cleanup review tray.
enum DiskReviewResolution {
    /// Entry matches or contains one or more scan findings; these are what get reviewed.
    case covered([ScanFinding])
    /// Entry sits inside a single larger finding; that finding, not the entry, should be reviewed.
    case insideFinding(ScanFinding)
    /// A scan ran, but nothing at this path is a review candidate.
    case notCandidate
    /// No Smart Scan findings are available yet.
    case noScan
}

/// Maps a Disk Analyzer path onto the latest Smart Scan findings so only scan-covered
/// items can reach the cleanup review tray (resolved decision 2026-09-26, #1).
enum DiskReviewResolver {

    /// `.advanced` findings are excluded up front so they can never surface as covered or as
    /// the blocking finding for `.insideFinding` — CleanupEngine hard-blocks their deletion anyway.
    static func resolve(entryPath: String, findings: [ScanFinding]) -> DiskReviewResolution {
        guard !findings.isEmpty else { return .noScan }

        let entryURL = URL(fileURLWithPath: entryPath)
        let candidates = findings.filter { $0.riskLevel != .advanced }

        let covering = candidates.filter { finding in
            ScanPolicy.isEqualToOrDescendant(candidate: URL(fileURLWithPath: finding.path), root: entryURL)
        }
        if !covering.isEmpty {
            return .covered(covering)
        }

        if let container = candidates.first(where: { finding in
            ScanPolicy.isEqualToOrDescendant(candidate: entryURL, root: URL(fileURLWithPath: finding.path))
        }) {
            return .insideFinding(container)
        }

        return .notCandidate
    }
}
