import Foundation

/// Collapses findings that name the same path, or sit inside another finding, so each byte counts once.
/// Paths compare case-insensitively; on a case-sensitive volume this can only merge findings or raise risk.
enum FindingDeduplicator {

    private struct Entry {
        let url: URL
        let key: [String]
        let ruleIndex: Int
        let inputOrder: Int
        var finding: ScanFinding
    }

    static func deduplicate(_ items: [(ruleIndex: Int, finding: ScanFinding)]) -> [ScanFinding] {
        let entries = items.enumerated().map { order, item in
            let url = ScanPolicy.canonicalPathURL(URL(fileURLWithPath: item.finding.path))
            return Entry(
                url: url,
                key: url.pathComponents.map { $0.lowercased() },
                ruleIndex: item.ruleIndex,
                inputOrder: order,
                finding: item.finding
            )
        }
        let sorted = mergeSamePath(entries).sorted { $0.key.lexicographicallyPrecedes($1.key) }
        return collapseDescendants(sorted)
            .sorted { $0.inputOrder < $1.inputOrder }
            .map(\.finding)
    }

    /// Same path: highest risk wins, then the lower rule index.
    private static func mergeSamePath(_ entries: [Entry]) -> [Entry] {
        var winners: [[String]: Entry] = [:]
        for entry in entries {
            guard let current = winners[entry.key] else {
                winners[entry.key] = entry
                continue
            }
            if outranks(entry, current) {
                winners[entry.key] = entry
            }
        }
        return Array(winners.values)
    }

    private static func outranks(_ lhs: Entry, _ rhs: Entry) -> Bool {
        let lhsSeverity = lhs.finding.riskLevel.severity
        let rhsSeverity = rhs.finding.riskLevel.severity
        if lhsSeverity != rhsSeverity { return lhsSeverity > rhsSeverity }
        return lhs.ruleIndex < rhs.ruleIndex
    }

    /// Expects component-wise sorted input, so every descendant follows its ancestor directly.
    private static func collapseDescendants(_ sorted: [Entry]) -> [Entry] {
        var kept: [Entry] = []
        var openAncestors: [Int] = []
        for entry in sorted {
            // Same-path entries are already merged, so containment here means a strict ancestor.
            while let top = openAncestors.last,
                  !ScanPolicy.isEqualToOrDescendant(candidate: entry.url, root: kept[top].url) {
                openAncestors.removeLast()
            }
            let cleanableAncestor = openAncestors.first { kept[$0].finding.riskLevel != .advanced }
            if let ancestor = cleanableAncestor {
                // A cleanable parent must carry its riskiest content so Quick Clean never deletes it unseen.
                let floor: RiskLevel = entry.finding.riskLevel == .advanced ? .review : entry.finding.riskLevel
                kept[ancestor].finding = raising(kept[ancestor].finding, to: floor)
                if entry.finding.riskLevel != .advanced { continue }
            }
            kept.append(entry)
            openAncestors.append(kept.count - 1)
        }
        return kept
    }

    private static func raising(_ finding: ScanFinding, to floor: RiskLevel) -> ScanFinding {
        guard floor.severity > finding.riskLevel.severity else { return finding }
        return ScanFinding(
            category: finding.category,
            riskLevel: floor,
            reason: finding.reason,
            path: finding.path,
            sizeBytes: finding.sizeBytes,
            lastUsed: finding.lastUsed,
            confidence: finding.confidence
        )
    }
}
