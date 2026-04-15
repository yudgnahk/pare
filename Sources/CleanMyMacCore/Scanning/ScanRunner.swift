import Foundation

public struct ScanRunner: Sendable {
    private let environment: ScanEnvironment
    private let traversal: any FileTraversing

    public init(
        environment: ScanEnvironment = .current(),
        traversal: any FileTraversing = FileSystemTraversal()
    ) {
        self.environment = environment
        self.traversal = traversal
    }

    public func run(rules: [any ScanRule]) async -> ScanReport {
        var findings: [ScanFinding] = []
        var grouped: [ScanCategory: (bytes: Int64, count: Int)] = [:]

        for rule in rules {
            let directories = rule.targetDirectories(environment: environment)
            let files = await traversal.collectFiles(in: directories)

            for file in files {
                guard include(file: file, rule: rule) else {
                    continue
                }

                findings.append(
                    ScanFinding(
                        category: rule.category,
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
}
