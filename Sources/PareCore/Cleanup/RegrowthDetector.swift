import Foundation

/// Spots findings that grew straight back after Pare trashed them (a tool's working set, e.g. a build cache)
/// and demotes them to `.review`, so Quick Clean and preselection stop proposing them.
public struct RegrowthDetector: Sendable {
    public static let regrowthWindowDays = 14
    /// Share of the trashed size that counts as "came back" (go-build: 6.93 GB trashed, 1.3 GB three hours later).
    public static let regrowthSizeRatio = 0.15
    /// This many cleans inside the window mark a working set regardless of current size.
    public static let repeatCleanCount = 2

    private let history: @Sendable () -> [CleanupTransaction]
    private let now: @Sendable () -> Date

    public init(store: CleanupTransactionStore = .shared, now: @escaping @Sendable () -> Date = { Date() }) {
        // Unreadable or corrupt history means no regrowth evidence, never a failed scan.
        self.init(history: { (try? store.loadAll()) ?? [] }, now: now)
    }

    init(history: @escaping @Sendable () -> [CleanupTransaction], now: @escaping @Sendable () -> Date) {
        self.history = history
        self.now = now
    }

    public func apply(to findings: [ScanFinding]) -> [ScanFinding] {
        let current = now()
        let cleans = recentCleans(since: current.addingTimeInterval(-Double(Self.regrowthWindowDays) * 86_400))
        guard !cleans.isEmpty else { return findings }
        return findings.map { (finding: ScanFinding) -> ScanFinding in
            guard finding.riskLevel != .advanced,
                  let past = cleans[Self.key(finding.path)],
                  let last = past.max(by: { $0.date < $1.date }) else { return finding }
            let regrew = last.bytes > 0 && Double(finding.sizeBytes) >= Double(last.bytes) * Self.regrowthSizeRatio
            guard regrew || past.count >= Self.repeatCleanCount else { return finding }
            return demoted(finding, sinceLastClean: current.timeIntervalSince(last.date))
        }
    }

    // MARK: - Private

    private func recentCleans(since cutoff: Date) -> [String: [(date: Date, bytes: Int64)]] {
        var cleans: [String: [(date: Date, bytes: Int64)]] = [:]
        for transaction in history() where !transaction.isDryRun && transaction.timestamp >= cutoff {
            for item in transaction.items {
                cleans[Self.key(item.originalPath), default: []].append((transaction.timestamp, item.sizeBytes))
            }
        }
        return cleans
    }

    private func demoted(_ finding: ScanFinding, sinceLastClean interval: TimeInterval) -> ScanFinding {
        let days = max(1, Int((interval / 86_400).rounded(.up)))
        let size = ByteCountFormatter.string(fromByteCount: finding.sizeBytes, countStyle: .file)
        return ScanFinding(
            category: finding.category,
            riskLevel: .review,
            reason: finding.reason + " — came back to \(size) within \(days) day\(days == 1 ? "" : "s") "
                + "of the last clean; likely an active working set",
            path: finding.path,
            sizeBytes: finding.sizeBytes,
            lastUsed: finding.lastUsed,
            confidence: finding.confidence
        )
    }

    private static func key(_ path: String) -> String {
        ScanPolicy.canonicalPathURL(URL(fileURLWithPath: path)).path.lowercased()
    }
}
