import Foundation

/// Folders holding a huge number of tiny files whose disk blocks far exceed their content
/// (e.g. 318k × ~250 B using 1.2 GB), left untouched for a month. Explain-only: the owning app
/// has to clear its own queue. Direct children only; bounded by an entry budget and a per-folder deadline.
public struct TinyFileQueueRule: ScanRule {
    public let id = "tiny-file-queues"
    public let title = "Folders of Tiny Files"
    public let reason = "Folder of tiny files using far more disk than its content"
    public let category: ScanCategory = .diagnostics
    public let riskLevel: RiskLevel = .advanced
    public let confidence: Double = 0.85

    public struct Thresholds: Sendable {
        public let minimumFileCount: Int
        public let tinyFileBytes: Int64
        public let minimumTinyFraction: Double
        public let minimumAllocatedToLogicalRatio: Double
        public let minimumAgeSeconds: TimeInterval

        public init(
            minimumFileCount: Int, tinyFileBytes: Int64, minimumTinyFraction: Double,
            minimumAllocatedToLogicalRatio: Double, minimumAgeSeconds: TimeInterval
        ) {
            self.minimumFileCount = minimumFileCount
            self.tinyFileBytes = tinyFileBytes
            self.minimumTinyFraction = minimumTinyFraction
            self.minimumAllocatedToLogicalRatio = minimumAllocatedToLogicalRatio
            self.minimumAgeSeconds = minimumAgeSeconds
        }

        public static let `default` = Thresholds(
            minimumFileCount: 100_000, tinyFileBytes: 4096, minimumTinyFraction: 0.9,
            minimumAllocatedToLogicalRatio: 4, minimumAgeSeconds: 30 * 24 * 60 * 60
        )
    }

    /// Directory entries listed per scan, across all roots.
    public static let defaultEntryBudget = 3_000_000
    /// Longest one candidate folder may take to measure; unfinished folders are not reported.
    public static let defaultPerDirectoryBudgetSeconds: TimeInterval = 5
    /// Levels below each root that are searched.
    static let maxDepth = 3
    /// Entries between clock reads while measuring a candidate.
    static let deadlineCheckInterval = 1024

    private let thresholds: Thresholds
    private let entryBudget: Int
    private let perDirectoryBudgetSeconds: TimeInterval
    private let now: @Sendable () -> Date

    public init(
        thresholds: Thresholds = .default,
        entryBudget: Int = TinyFileQueueRule.defaultEntryBudget,
        perDirectoryBudgetSeconds: TimeInterval = TinyFileQueueRule.defaultPerDirectoryBudgetSeconds,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.thresholds = thresholds
        self.entryBudget = entryBudget
        self.perDirectoryBudgetSeconds = perDirectoryBudgetSeconds
        self.now = now
    }

    public func targetDirectories(environment: ScanEnvironment) -> [URL] { [] }
    public func include(fileURL: URL, resourceValues: URLResourceValues) -> Bool { false }

    public func customScan(environment: ScanEnvironment) async -> [ScanFinding]? {
        var budget = entryBudget
        var findings: [ScanFinding] = []
        for root in Self.roots(home: environment.homeDirectory) {
            guard budget > 0, !Task.isCancelled else { break }
            var pending = [(url: root, depth: 0)]
            while let next = pending.popLast(), budget > 0, !Task.isCancelled {
                guard let listing = Self.list(next.url, budget: &budget) else { break }
                if listing.entryCount >= thresholds.minimumFileCount,
                   let stats = measure(next.url), let finding = finding(for: next.url, stats: stats, app: root.lastPathComponent) {
                    findings.append(finding)
                }
                if next.depth < Self.maxDepth {
                    pending += listing.subdirectories.map { ($0, next.depth + 1) }
                }
            }
        }
        return findings
    }

    // MARK: - Walk

    /// `~/Library/Application Support/*`, `~/Library/Caches/*` and `~` dot directories (not the Trash).
    static func roots(home: URL) -> [URL] {
        let dotDirectories = subdirectories(of: home).filter {
            $0.lastPathComponent.hasPrefix(".") && $0.lastPathComponent != ".Trash"
        }
        return subdirectories(of: home.appending(path: "Library/Application Support"))
            + subdirectories(of: home.appending(path: "Library/Caches"))
            + dotDirectories
    }

    private static func subdirectories(of url: URL) -> [URL] {
        var budget = Int.max
        return list(url, budget: &budget)?.subdirectories ?? []
    }

    /// Pass 1, cheap: direct children with only the directory flag. Nil when the budget runs out mid-listing.
    private static func list(_ url: URL, budget: inout Int) -> (entryCount: Int, subdirectories: [URL])? {
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey]
        guard let enumerator = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: keys, options: [.skipsSubdirectoryDescendants]
        ) else { return (0, []) }
        var count = 0
        var subdirectories: [URL] = []
        for case let child as URL in enumerator {
            guard budget > 0 else { return nil }
            budget -= 1
            count += 1
            let values = try? child.resourceValues(forKeys: Set(keys))
            if values?.isDirectory == true, values?.isSymbolicLink != true {
                subdirectories.append(child)
            }
        }
        return (count, subdirectories)
    }

    private struct Stats {
        var files = 0
        var tiny = 0
        var logical: Int64 = 0
        var allocated: Int64 = 0
        var newest: Date?
    }

    /// Pass 2, only for folders with enough entries: sizes and dates of the direct child files.
    /// Nil when the per-folder deadline passes first.
    private func measure(_ url: URL) -> Stats? {
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .totalFileAllocatedSizeKey,
                                      .fileAllocatedSizeKey, .contentModificationDateKey]
        guard let enumerator = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: keys, options: [.skipsSubdirectoryDescendants]
        ) else { return nil }
        let deadline = now().addingTimeInterval(perDirectoryBudgetSeconds)
        var stats = Stats()
        var visited = 0
        for case let child as URL in enumerator {
            if visited % Self.deadlineCheckInterval == 0, now() >= deadline || Task.isCancelled { return nil }
            visited += 1
            guard let values = try? child.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else { continue }
            let size = Int64(values.fileSize ?? 0)
            stats.files += 1
            stats.logical += size
            stats.allocated += Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
            if size < thresholds.tinyFileBytes { stats.tiny += 1 }
            if let date = values.contentModificationDate { stats.newest = max(stats.newest ?? date, date) }
        }
        return stats
    }

    // MARK: - Finding

    private func finding(for url: URL, stats: Stats, app: String) -> ScanFinding? {
        guard stats.files >= thresholds.minimumFileCount,
              Double(stats.tiny) >= thresholds.minimumTinyFraction * Double(stats.files),
              stats.allocated > 0,
              Double(stats.allocated) >= thresholds.minimumAllocatedToLogicalRatio * Double(max(stats.logical, 1)),
              let newest = stats.newest, now().timeIntervalSince(newest) >= thresholds.minimumAgeSeconds else { return nil }
        let count = Self.grouped(stats.files)
        let average = ByteCountFormatter.string(fromByteCount: stats.logical / Int64(stats.files), countStyle: .file)
        let onDisk = ByteCountFormatter.string(fromByteCount: stats.allocated, countStyle: .file)
        return ScanFinding(
            category: category,
            riskLevel: riskLevel,
            reason: "\(count) tiny files (avg \(average)) use \(onDisk) on disk — \(app) queue; clear it from the app or contact its support",
            path: url.path,
            sizeBytes: stats.allocated,
            lastUsed: newest,
            confidence: confidence,
            annotations: [.explainOnly(action: "Clear it from \(app) or contact its support")]
        )
    }

    private static func grouped(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }
}
