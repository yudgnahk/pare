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

    public func run(rules: [any ScanRule], forceRescan: Bool = false) async -> ScanReport {
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

        for rule in rules {
            guard !Task.isCancelled else { break }
            let (ruleFindings, ruleGrouped) = await runRule(rule, traversal: effectiveTraversal)
            findings.append(contentsOf: ruleFindings)
            for (category, value) in ruleGrouped {
                let current = grouped[category] ?? (0, 0)
                grouped[category] = (current.0 + value.0, current.1 + value.1)
            }
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

        return ScanReport(findings: findings, summaries: summaries)
    }

    private func runRule(
        _ rule: any ScanRule,
        traversal: any FileTraversing
    ) async -> ([ScanFinding], [ScanCategory: (Int64, Int)]) {
        var localFindings: [ScanFinding] = []
        var localGrouped: [ScanCategory: (Int64, Int)] = [:]

        if let customFindings = await rule.customScan(environment: environment) {
            for finding in customFindings where !exclusionList.isExcluded(finding.path) {
                localFindings.append(finding)
                let current = localGrouped[finding.category] ?? (0, 0)
                localGrouped[finding.category] = (current.0 + finding.sizeBytes, current.1 + 1)
            }
            return (localFindings, localGrouped)
        }

        let directories = rule.targetDirectories(environment: environment)
        let files = await traversal.collectFiles(in: directories)

        for file in files {
            guard !Task.isCancelled else { break }
            guard include(file: file, rule: rule) else { continue }
            guard !exclusionList.isExcluded(file.url.path) else { continue }

            localFindings.append(ScanFinding(
                category: rule.category,
                riskLevel: rule.riskLevel,
                reason: rule.reason,
                path: file.url.path,
                sizeBytes: file.sizeBytes,
                lastUsed: file.lastModified,
                confidence: rule.confidence
            ))
            let current = localGrouped[rule.category] ?? (0, 0)
            localGrouped[rule.category] = (current.0 + file.sizeBytes, current.1 + 1)
        }

        return (localFindings, localGrouped)
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
