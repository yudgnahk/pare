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
/// items can reach the cleanup review tray.
enum DiskReviewResolver {

    /// `.advanced` findings are excluded up front so they can never surface as covered or as
    /// the blocking finding for `.insideFinding` — CleanupEngine hard-blocks their deletion anyway.
    /// `isCaseSensitive` answers for the entry's volume; injected so tests need no case-sensitive volume.
    static func resolve(
        entryPath: String,
        findings: [ScanFinding],
        isCaseSensitive: (String) -> Bool = ScanPolicy.volumeSupportsCaseSensitiveNames(atPath:)
    ) -> DiskReviewResolution {
        guard !findings.isEmpty else { return .noScan }

        let candidates = findings.filter { $0.riskLevel != .advanced }
        let caseSensitive = isCaseSensitive(entryPath)

        let covering = candidates.filter { finding in
            contains(finding.path, root: entryPath, caseSensitive: caseSensitive)
        }
        if !covering.isEmpty {
            return .covered(covering)
        }

        if let container = candidates
            .filter({ contains(entryPath, root: $0.path, caseSensitive: caseSensitive) })
            .max(by: { componentCount($0.path) < componentCount($1.path) }) {
            return .insideFinding(container)
        }

        return .notCandidate
    }

    private static func contains(_ candidate: String, root: String, caseSensitive: Bool) -> Bool {
        ScanPolicy.isCanonicallyEqualToOrDescendant(
            candidate: URL(fileURLWithPath: candidate),
            root: URL(fileURLWithPath: root),
            caseSensitive: caseSensitive
        )
    }

    private static func componentCount(_ path: String) -> Int {
        ScanPolicy.canonicalPathURL(URL(fileURLWithPath: path)).pathComponents.count
    }
}
