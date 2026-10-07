import Foundation

/// How recently a cache was written: hot caches are in active use, cold ones have sat untouched for a long time.
public enum CacheActivity: String, Sendable, Equatable {
    case hot, warm, cold
}

public enum CacheActivityClassifier {
    /// Defaults pending a product decision on the hot/cold cut-offs.
    public static let defaultHotDays = 3
    public static let defaultColdDays = 30

    /// Newest entry within `hotDays` (or in the future) is hot, none newer than `coldDays` is cold, unknown is warm.
    public static func classify(
        newestEntryDate: Date?,
        now: Date,
        hotDays: Int = defaultHotDays,
        coldDays: Int = defaultColdDays
    ) -> CacheActivity {
        guard let newestEntryDate else { return .warm }
        let age = now.timeIntervalSince(newestEntryDate)
        if age <= Double(hotDays) * 86_400 { return .hot }
        if age >= Double(coldDays) * 86_400 { return .cold }
        return .warm
    }
}

/// Display-only activity for one finding; never changes risk or preselection.
public struct CacheActivityLabel: Sendable, Equatable {
    public let activity: CacheActivity
    public let newestEntryDate: Date?

    public init(activity: CacheActivity, newestEntryDate: Date?) {
        self.activity = activity
        self.newestEntryDate = newestEntryDate
    }

    public func text(now: Date) -> String {
        guard let newestEntryDate else { return "Last use unknown" }
        let days = max(0, Int(now.timeIntervalSince(newestEntryDate) / 86_400))
        switch activity {
        case .hot: return "In active use"
        case .warm: return "Last used \(days) day\(days == 1 ? "" : "s") ago"
        case .cold: return "Not used in \(days) days"
        }
    }
}

/// Newest modification date under a cache, sampled within an entry cap, a depth limit and a deadline.
/// Uses mtime only: `atime` is unreliable on APFS.
public enum CacheActivitySampler {
    public static let defaultMaxEntries = 2_000
    public static let defaultMaxDepth = 2

    public struct Sample: Sendable, Equatable {
        public let newest: Date?
        public let sampledEntries: Int
        /// False when the cap or deadline stopped the walk early.
        public let isComplete: Bool
    }

    public static func sample(
        _ url: URL,
        maxEntries: Int = defaultMaxEntries,
        maxDepth: Int = defaultMaxDepth,
        deadline: Date,
        clock: () -> Date = { Date() }
    ) -> Sample {
        let key: URLResourceKey = .contentModificationDateKey
        var newest = (try? url.resourceValues(forKeys: [key, .isDirectoryKey]))?.contentModificationDate
        guard (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true,
              let enumerator = FileManager.default.enumerator(
                at: url, includingPropertiesForKeys: [key, .isDirectoryKey], options: [.skipsPackageDescendants]
              ) else {
            return Sample(newest: newest, sampledEntries: 0, isComplete: true)
        }
        var count = 0
        for case let entry as URL in enumerator {
            guard count < maxEntries, clock() < deadline else {
                return Sample(newest: newest, sampledEntries: count, isComplete: false)
            }
            count += 1
            let values = try? entry.resourceValues(forKeys: [key, .isDirectoryKey])
            if let date = values?.contentModificationDate, date > (newest ?? .distantPast) { newest = date }
            if values?.isDirectory == true, enumerator.level >= maxDepth { enumerator.skipDescendants() }
        }
        return Sample(newest: newest, sampledEntries: count, isComplete: true)
    }
}

/// Labels `.safe`/`.review` cache findings with their activity, largest first, within one overall time budget.
public enum CacheActivityLabeler {
    public static let defaultBudgetSeconds: TimeInterval = 3
    public static let perFindingSeconds: TimeInterval = 0.25

    static let cacheCategories: Set<ScanCategory> = [
        .userCaches, .browserCaches, .developerPackageCaches, .developerSimulatorCaches,
        .designerCaches, .videoBuilderCaches, .aiToolCaches, .productivityCaches,
    ]

    public static func labels(
        for findings: [ScanFinding],
        now: Date = Date(),
        budgetSeconds: TimeInterval = defaultBudgetSeconds
    ) -> [String: CacheActivityLabel] {
        let overall = Date().addingTimeInterval(budgetSeconds)
        let candidates = findings
            .filter { $0.riskLevel != .advanced && cacheCategories.contains($0.category) }
            .sorted { $0.sizeBytes > $1.sizeBytes }
        var labels: [String: CacheActivityLabel] = [:]
        for finding in candidates {
            guard Date() < overall else { break }
            let deadline = min(overall, Date().addingTimeInterval(perFindingSeconds))
            let newest = CacheActivitySampler.sample(URL(fileURLWithPath: finding.path), deadline: deadline).newest
            labels[finding.path] = CacheActivityLabel(
                activity: CacheActivityClassifier.classify(newestEntryDate: newest, now: now),
                newestEntryDate: newest
            )
        }
        return labels
    }
}
