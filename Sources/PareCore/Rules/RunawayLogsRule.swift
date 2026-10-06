import Foundation

/// Explain-only: a single large log outside `~/Library/Logs` that is still being written is growing without rotation.
/// Pare never deletes a live log (the writer keeps its handle open), so this only tells the user where the space went.
public struct RunawayLogsRule: ScanRule {
    public let id = "runaway-logs"
    public let title = "Runaway Logs"
    public let reason = "Live log growing without rotation (explain only)"
    public let category: ScanCategory = .logsAndCrashReports
    public let riskLevel: RiskLevel = .advanced
    public let confidence: Double = 0.85

    public static let minimumBytes: Int64 = 200 * 1024 * 1024
    /// Written this recently means a live, unrotated log rather than an old leftover.
    public static let activeWithin: TimeInterval = 24 * 60 * 60
    static let logExtensions: Set<String> = ["log", "out", "err"]
    /// Shared cap on visited entries so deep dot-directories cannot slow the scan.
    static let entryBudget = 100_000

    private let now: @Sendable () -> Date

    public init(now: @escaping @Sendable () -> Date = { Date() }) {
        self.now = now
    }

    public func targetDirectories(environment: ScanEnvironment) -> [URL] { [] }
    public func include(fileURL: URL, resourceValues: URLResourceValues) -> Bool { false }

    public func customScan(environment: ScanEnvironment) async -> [ScanFinding]? {
        let activeSince = now().addingTimeInterval(-Self.activeWithin)
        var budget = Self.entryBudget
        var findings: [ScanFinding] = []
        for (root, maxDepth) in Self.searchRoots(environment: environment) {
            guard budget > 0, !Task.isCancelled else { break }
            findings += scan(root: root, maxDepth: maxDepth, activeSince: activeSince, budget: &budget)
        }
        return findings
    }

    // MARK: - Private

    /// `Application Support/<app>/…/x.log`, `~/.<tool>/logs/x.log`, and the scan's temp directory.
    /// `~/Library/Logs` is deliberately absent: `LogsAndCrashReportsRule` owns it.
    static func searchRoots(environment: ScanEnvironment) -> [(URL, Int)] {
        let home = environment.homeDirectory
        let dotDirectories = ((try? FileManager.default.contentsOfDirectory(
            at: home, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey]
        )) ?? []).filter { url in
            let name = url.lastPathComponent
            guard name.hasPrefix("."), name != ".Trash",
                  let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]) else { return false }
            return values.isDirectory == true && values.isSymbolicLink != true
        }
        .sorted { $0.path < $1.path }
        return [(home.appending(path: "Library/Application Support"), 4)]
            + dotDirectories.map { ($0, 3) }
            + [(environment.tempDirectory, 2)]
    }

    private func scan(root: URL, maxDepth: Int, activeSince: Date, budget: inout Int) -> [ScanFinding] {
        let keys: [URLResourceKey] = [
            .isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey,
        ]
        guard let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: keys, options: [.skipsPackageDescendants]
        ) else { return [] }
        var findings: [ScanFinding] = []
        for case let url as URL in enumerator {
            budget -= 1
            guard budget > 0, !Task.isCancelled else { break }
            guard let values = try? url.resourceValues(forKeys: Set(keys)), values.isSymbolicLink != true else { continue }
            if values.isDirectory == true {
                if enumerator.level >= maxDepth { enumerator.skipDescendants() }
                continue
            }
            guard values.isRegularFile == true,
                  Self.logExtensions.contains(url.pathExtension.lowercased()),
                  let size = values.fileSize, Int64(size) >= Self.minimumBytes,
                  let modified = values.contentModificationDate, modified >= activeSince else { continue }
            findings.append(finding(for: url, bytes: Int64(size), modified: modified))
        }
        return findings
    }

    private func finding(for url: URL, bytes: Int64, modified: Date) -> ScanFinding {
        let size = ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
        return ScanFinding(
            category: category,
            riskLevel: riskLevel,
            reason: "\(url.lastPathComponent) is \(size) and was written in the last day, so it is still growing "
                + "without rotation. Truncate or rotate it via the app; Pare won't delete live logs.",
            path: url.path,
            sizeBytes: bytes,
            lastUsed: modified,
            confidence: confidence
        )
    }
}
