import Foundation

public struct ScanRunner: Sendable {
    private let environment: ScanEnvironment
    private let traversal: any FileTraversing
    private let exclusionList: ExclusionList
    private let cache: ScanMetadataCache?

    public init(
        environment: ScanEnvironment = .current(),
        traversal: any FileTraversing = FileSystemTraversal(),
        exclusionList: ExclusionList = .empty,
        cache: ScanMetadataCache? = nil
    ) {
        self.environment = environment
        self.traversal = traversal
        self.exclusionList = exclusionList
        self.cache = cache
    }

    /// Progress callback: (completedRules, totalRules, lastRuleTitle).
    public typealias ProgressHandler = @Sendable (Int, Int, String) -> Void

    public func run(
        rules: [any ScanRule],
        forceRescan: Bool = false,
        onProgress: ProgressHandler? = nil
    ) async -> ScanReport {
        let effectiveTraversal: any FileTraversing
        if let cache {
            let fingerprint = rules.map(\.id).sorted().joined(separator: ",")
            await cache.setProfile(fingerprint)
            if forceRescan {
                await cache.invalidate()
            }
            effectiveTraversal = CachedFileTraversal(inner: traversal, cache: cache)
        } else {
            effectiveTraversal = traversal
        }

        var findings: [ScanFinding] = []
        var grouped: [ScanCategory: (Int64, Int)] = [:]
        let total = rules.count
        // Fresh per-scan size index: rules sizing overlapping trees share one
        // walk per directory within this run, but never across runs.
        let runEnvironment = environment.withFreshSizeIndex()

        for (index, rule) in rules.enumerated() {
            guard !Task.isCancelled else { break }
            let (ruleFindings, ruleGrouped) = await runRule(
                rule,
                environment: runEnvironment,
                traversal: effectiveTraversal
            )
            findings.append(contentsOf: ruleFindings)
            for (category, value) in ruleGrouped {
                let current = grouped[category] ?? (0, 0)
                grouped[category] = (current.0 + value.0, current.1 + value.1)
            }
            onProgress?(index + 1, total, rule.title)
        }

        // Persist the mtime index once per scan (stores only mark it dirty).
        await cache?.flush()

        let summaries = grouped
            .map { category, value in
                ScanCategorySummary(
                    category: category,
                    reclaimableBytes: value.0,
                    fileCount: value.1
                )
            }
            .sorted { $0.reclaimableBytes > $1.reclaimableBytes }

        return ScanReport(findings: findings, summaries: summaries)
    }

    private func runRule(
        _ rule: any ScanRule,
        environment: ScanEnvironment,
        traversal: any FileTraversing
    ) async -> ([ScanFinding], [ScanCategory: (Int64, Int)]) {
        var localFindings: [ScanFinding] = []
        var localGrouped: [ScanCategory: (Int64, Int)] = [:]

        if let customFindings = await rule.customScan(environment: environment) {
            for finding in customFindings where !exclusionList.isExcluded(finding.path) {
                localFindings.append(finding)
                accumulateReclaimable(finding, into: &localGrouped)
            }
            return (localFindings, localGrouped)
        }

        let directories = rule.targetDirectories(environment: environment)
        let files = await traversal.collectFiles(in: directories)

        for file in files {
            guard !Task.isCancelled else { break }
            guard include(file: file, rule: rule) else { continue }
            guard !exclusionList.isExcluded(file.url.path) else { continue }

            let finding = ScanFinding(
                category: rule.category,
                riskLevel: rule.riskLevel,
                reason: rule.reason,
                path: file.url.path,
                sizeBytes: file.sizeBytes,
                lastUsed: file.lastModified,
                confidence: rule.confidence
            )
            localFindings.append(finding)
            accumulateReclaimable(finding, into: &localGrouped)
        }

        return (localFindings, localGrouped)
    }

    /// Category summaries and `totalReclaimableBytes` only include cleanable findings.
    /// `.advanced` items stay in `findings` for visibility but must not inflate reclaimable totals.
    private func accumulateReclaimable(
        _ finding: ScanFinding,
        into grouped: inout [ScanCategory: (Int64, Int)]
    ) {
        guard finding.riskLevel != .advanced else { return }
        let current = grouped[finding.category] ?? (0, 0)
        grouped[finding.category] = (current.0 + finding.sizeBytes, current.1 + 1)
    }

    private func include(file: ScannedFile, rule: any ScanRule) -> Bool {
        var values = URLResourceValues()
        values.contentModificationDate = file.lastModified
        return rule.include(fileURL: file.url, resourceValues: values)
    }
}

public extension Array where Element == any ScanRule {
    static var baseline: [any ScanRule] {
        RuleCatalog.baseline
    }

    static var developer: [any ScanRule] {
        RuleCatalog.developer
    }

    static var designer: [any ScanRule] {
        RuleCatalog.designer
    }

    static var videoBuilder: [any ScanRule] {
        RuleCatalog.videoBuilder
    }
}
