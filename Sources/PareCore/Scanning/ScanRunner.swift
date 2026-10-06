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

        var tagged: [(ruleIndex: Int, finding: ScanFinding)] = []
        var ruleFailures: [ScanRuleFailure] = []
        var incompleteRules: [ScanIncompleteRule] = []
        var unreadable: Set<String> = []
        let total = rules.count
        // Fresh per-scan size index: rules sizing overlapping trees share one
        // walk per directory within this run, but never across runs.
        let runEnvironment = environment.withFreshSizeIndex()

        for (index, rule) in rules.enumerated() {
            guard !Task.isCancelled else { break }
            let outcome = await runRule(
                rule,
                environment: runEnvironment,
                traversal: effectiveTraversal
            )
            tagged.append(contentsOf: outcome.findings.map { (ruleIndex: index, finding: $0) })
            if let failure = outcome.failure {
                ruleFailures.append(failure)
            }
            if let incomplete = outcome.incomplete {
                incompleteRules.append(incomplete)
            }
            unreadable.formUnion(outcome.unreadablePaths)
            onProgress?(index + 1, total, rule.title)
        }

        // Persist the mtime index once per scan (stores only mark it dirty).
        await cache?.flush()

        // Rules overlap (same folder, or a folder and files inside it); totals must count each path once.
        let findings = FindingDeduplicator.deduplicate(tagged)
        var grouped: [ScanCategory: (Int64, Int)] = [:]
        for finding in findings {
            accumulateReclaimable(finding, into: &grouped)
        }
        let summaries = grouped
            .map { category, value in
                ScanCategorySummary(
                    category: category,
                    reclaimableBytes: value.0,
                    fileCount: value.1
                )
            }
            .sorted { $0.reclaimableBytes > $1.reclaimableBytes }

        return ScanReport(
            findings: findings,
            summaries: summaries,
            ruleFailures: ruleFailures,
            unreadableLocations: unreadable.sorted(),
            incompleteRules: incompleteRules
        )
    }

    private struct RuleOutcome {
        var findings: [ScanFinding] = []
        var unreadablePaths: Set<String> = []
        var failure: ScanRuleFailure? = nil
        var incomplete: ScanIncompleteRule? = nil
    }

    private func runRule(
        _ rule: any ScanRule,
        environment: ScanEnvironment,
        traversal: any FileTraversing
    ) async -> RuleOutcome {
        var outcome = RuleOutcome()

        do {
            if let result = try await rule.customScanResult(environment: environment) {
                outcome.findings = result.findings.filter { !exclusionList.isExcluded($0.path) }
                outcome.incomplete = result.incompleteMessage.map {
                    ScanIncompleteRule(ruleID: rule.id, ruleTitle: rule.title, message: $0)
                }
                return outcome
            }
        } catch {
            // R1.2: a throwing rule is a failed rule — report it, never mask it
            // as "found nothing".
            outcome.failure = ScanRuleFailure(
                ruleID: rule.id,
                ruleTitle: rule.title,
                message: error.localizedDescription
            )
            return outcome
        }

        let directories = rule.targetDirectories(environment: environment)
        let result = await traversal.collectFilesReportingErrors(in: directories)
        outcome.unreadablePaths = result.unreadablePaths

        for file in result.files {
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
            outcome.findings.append(finding)
        }

        return outcome
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
