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
        var grouped: [ScanCategory: (bytes: Int64, count: Int)] = [:]

        for rule in rules {
            guard !Task.isCancelled else { break }

            // Rules that need directory-level reasoning produce findings themselves.
            if let customFindings = await rule.customScan(environment: environment) {
                for finding in customFindings where !exclusionList.isExcluded(finding.path) {
                    findings.append(finding)
                    let current = grouped[finding.category] ?? (0, 0)
                    grouped[finding.category] = (
                        bytes: current.bytes + finding.sizeBytes,
                        count: current.count + 1
                    )
                }
                continue
            }

            let directories = rule.targetDirectories(environment: environment)
            let files = await effectiveTraversal.collectFiles(in: directories)

            for file in files {
                guard include(file: file, rule: rule) else {
                    continue
                }
                guard !exclusionList.isExcluded(file.url.path) else {
                    continue
                }

                findings.append(
                    ScanFinding(
                        category: rule.category,
                        riskLevel: rule.riskLevel,
                        reason: rule.reason,
                        path: file.url.path,
                        sizeBytes: file.sizeBytes,
                        lastUsed: file.lastModified,
                        confidence: rule.confidence
                    )
                )

                let current = grouped[rule.category] ?? (0, 0)
                grouped[rule.category] = (
                    bytes: current.bytes + file.sizeBytes,
                    count: current.count + 1
                )
            }
        }

        let summaries = grouped
            .map { category, value in
                ScanCategorySummary(
                    category: category,
                    reclaimableBytes: value.bytes,
                    fileCount: value.count
                )
            }
            .sorted { $0.reclaimableBytes > $1.reclaimableBytes }

        return ScanReport(findings: findings, summaries: summaries)
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
