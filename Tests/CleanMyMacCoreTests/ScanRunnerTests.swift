import XCTest
@testable import App BCore

final class ScanRunnerTests: XCTestCase {
    struct MockTraversal: FileTraversing {
        let filesByDirectory: [String: [ScannedFile]]

        func collectFiles(in directories: [URL]) async -> [ScannedFile] {
            directories.flatMap { filesByDirectory[$0.path] ?? [] }
        }
    }

    struct TestRule: ScanRule {
        let id: String
        let title: String
        let category: ScanCategory
        let riskLevel: RiskLevel = .safe
        let confidence: Double = 1.0
        let targets: [URL]

        func targetDirectories(environment: ScanEnvironment) -> [URL] {
            targets
        }

        func include(fileURL: URL, resourceValues: URLResourceValues) -> Bool {
            true
        }
    }

    func testBaselineRuleIncludesKnownRules() {
        let rules = [any ScanRule].baseline
        XCTAssertEqual(rules.count, 4)
        XCTAssertTrue(rules.contains(where: { $0.id == "user-caches" }))
        XCTAssertTrue(rules.contains(where: { $0.id == "temporary-files" }))
        XCTAssertTrue(rules.contains(where: { $0.id == "logs-crash-reports" }))
        XCTAssertTrue(rules.contains(where: { $0.id == "browser-caches" }))
    }

    func testBrowserRuleSkipsSensitiveFiles() {
        let rule = BrowserCachesRule()
        let values = URLResourceValues()

        XCTAssertFalse(
            rule.include(
                fileURL: URL(fileURLWithPath: "/Users/test/Library/Caches/Google/Chrome/Default/History"),
                resourceValues: values
            )
        )

        XCTAssertTrue(
            rule.include(
                fileURL: URL(fileURLWithPath: "/Users/test/Library/Caches/Google/Chrome/Default/Code Cache/js"),
                resourceValues: values
            )
        )
    }

    func testTemporaryRuleRequiresMinimumAge() {
        let rule = TemporaryFilesRule()

        var oldValues = URLResourceValues()
        oldValues.contentModificationDate = Date().addingTimeInterval(-2 * 24 * 60 * 60)

        var newValues = URLResourceValues()
        newValues.contentModificationDate = Date()

        XCTAssertTrue(
            rule.include(
                fileURL: URL(fileURLWithPath: "/private/var/folders/tmp/app.tmp"),
                resourceValues: oldValues
            )
        )

        XCTAssertFalse(
            rule.include(
                fileURL: URL(fileURLWithPath: "/private/var/folders/tmp/app.tmp"),
                resourceValues: newValues
            )
        )
    }

    func testDeveloperRuleCatalogIncludesPersonaRules() {
        let rules = [any ScanRule].developer
        XCTAssertTrue(rules.contains(where: { $0.id == "xcode-derived-data" }))
        XCTAssertTrue(rules.contains(where: { $0.id == "xcode-archives" }))
        XCTAssertTrue(rules.contains(where: { $0.id == "package-manager-caches" }))
        XCTAssertTrue(rules.contains(where: { $0.id == "xcode-simulator-caches" }))
        XCTAssertTrue(rules.count > [any ScanRule].baseline.count)
    }

    func testScanRunnerAggregatesBytesAndCountsByCategory() async {
        let cacheDir = URL(fileURLWithPath: "/tmp/cache")
        let logDir = URL(fileURLWithPath: "/tmp/log")

        let filesByDirectory = [
            cacheDir.path: [
                ScannedFile(url: cacheDir.appendingPathComponent("a.cache"), sizeBytes: 100, lastModified: nil),
                ScannedFile(url: cacheDir.appendingPathComponent("b.cache"), sizeBytes: 300, lastModified: nil)
            ],
            logDir.path: [
                ScannedFile(url: logDir.appendingPathComponent("app.log"), sizeBytes: 200, lastModified: nil)
            ]
        ]

        let traversal = MockTraversal(filesByDirectory: filesByDirectory)
        let runner = ScanRunner(
            environment: ScanEnvironment(homeDirectory: URL(fileURLWithPath: "/Users/test"), tempDirectory: URL(fileURLWithPath: "/tmp")),
            traversal: traversal
        )

        let rules: [any ScanRule] = [
            TestRule(id: "cache", title: "Cache", category: .userCaches, targets: [cacheDir]),
            TestRule(id: "logs", title: "Logs", category: .logsAndCrashReports, targets: [logDir])
        ]

        let report = await runner.run(rules: rules)
        XCTAssertEqual(report.findings.count, 3)
        XCTAssertEqual(report.totalReclaimableBytes, 600)

        let cacheSummary = report.summaries.first(where: { $0.category == .userCaches })
        XCTAssertEqual(cacheSummary?.reclaimableBytes, 400)
        XCTAssertEqual(cacheSummary?.fileCount, 2)

        let logSummary = report.summaries.first(where: { $0.category == .logsAndCrashReports })
        XCTAssertEqual(logSummary?.reclaimableBytes, 200)
        XCTAssertEqual(logSummary?.fileCount, 1)
    }
}
