import XCTest
@testable import CleanMyMacCore

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
        let reason: String
        let category: ScanCategory
        let riskLevel: RiskLevel
        let confidence: Double = 1.0
        let targets: [URL]

        init(id: String, title: String, reason: String = "Test finding", category: ScanCategory, riskLevel: RiskLevel = .safe, targets: [URL]) {
            self.id = id
            self.title = title
            self.reason = reason
            self.category = category
            self.riskLevel = riskLevel
            self.targets = targets
        }

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
        oldValues.contentModificationDate = Date().addingTimeInterval(-4 * 24 * 60 * 60)

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

    func testTemporaryRuleRejectsFilesNewerThanDefaultCacheAge() {
        let rule = TemporaryFilesRule()

        var values = URLResourceValues()
        values.contentModificationDate = Date().addingTimeInterval(-2 * 24 * 60 * 60)

        XCTAssertFalse(
            rule.include(
                fileURL: URL(fileURLWithPath: "/private/var/folders/tmp/too-new.tmp"),
                resourceValues: values
            )
        )
    }

    func testScanPolicyLargeFileThreshold() {
        XCTAssertFalse(ScanPolicy.isLargeFile(ScanPolicy.largeFileThresholdBytes))
        XCTAssertTrue(ScanPolicy.isLargeFile(ScanPolicy.largeFileThresholdBytes + 1))
    }

    func testScanPolicyRejectsProtectedPaths() {
        XCTAssertFalse(ScanPolicy.isLowImpactPath(URL(fileURLWithPath: "/Users/test/Documents/archive.cache")))
        XCTAssertFalse(ScanPolicy.isLowImpactPath(URL(fileURLWithPath: "/Users/test/Library/Application Support/App/data.cache")))
        XCTAssertTrue(ScanPolicy.isLowImpactPath(URL(fileURLWithPath: "/Users/test/Library/Caches/com.example/cache.db")))
    }

    func testDeveloperRuleCatalogIncludesPersonaRules() {
        let rules = [any ScanRule].developer
        XCTAssertTrue(rules.contains(where: { $0.id == "xcode-derived-data" }))
        XCTAssertTrue(rules.contains(where: { $0.id == "xcode-archives" }))
        XCTAssertTrue(rules.contains(where: { $0.id == "package-manager-caches" }))
        XCTAssertTrue(rules.contains(where: { $0.id == "xcode-simulator-caches" }))
        XCTAssertTrue(rules.contains(where: { $0.id == "vscode-caches" }))
        XCTAssertTrue(rules.contains(where: { $0.id == "vscode-review-required-state" }))
        XCTAssertTrue(rules.contains(where: { $0.id == "jetbrains-review-required" }))
        XCTAssertTrue(rules.contains(where: { $0.id == "docker-logs-review-required" }))
        XCTAssertTrue(rules.contains(where: { $0.id == "docker-vm-data-advanced" }))
        XCTAssertTrue(rules.count > [any ScanRule].baseline.count)
    }

    func testVSCodeCachesRuleIncludesOnlySafeDeveloperMarkers() {
        let rule = VSCodeCachesRule()

        var oldValues = URLResourceValues()
        oldValues.contentModificationDate = Date().addingTimeInterval(-4 * 24 * 60 * 60)

        XCTAssertTrue(
            rule.include(
                fileURL: URL(fileURLWithPath: "/Users/test/Library/Caches/com.microsoft.VSCode.ShipIt/update.pkg"),
                resourceValues: oldValues
            )
        )

        XCTAssertTrue(
            rule.include(
                fileURL: URL(fileURLWithPath: "/Users/test/Library/Application Support/Code/CachedExtensionVSIXs/cache.vsix"),
                resourceValues: oldValues
            )
        )

        XCTAssertFalse(
            rule.include(
                fileURL: URL(fileURLWithPath: "/Users/test/Library/Application Support/Code/User/workspaceStorage/state.json"),
                resourceValues: oldValues
            )
        )
    }

    func testVSCodeReviewRuleIncludesOnlyReviewMarkersAndExcludesSensitivePaths() {
        let rule = VSCodeReviewRequiredStateRule()

        var oldValues = URLResourceValues()
        oldValues.contentModificationDate = Date().addingTimeInterval(-4 * 24 * 60 * 60)

        XCTAssertTrue(
            rule.include(
                fileURL: URL(fileURLWithPath: "/Users/test/Library/Application Support/Code/User/workspaceStorage/abc/state.vscdb"),
                resourceValues: oldValues
            )
        )

        XCTAssertTrue(
            rule.include(
                fileURL: URL(fileURLWithPath: "/Users/test/.vscode/extensions/ms-python.python-2026.1.0/extension.vsixmanifest"),
                resourceValues: oldValues
            )
        )

        XCTAssertFalse(
            rule.include(
                fileURL: URL(fileURLWithPath: "/Users/test/Library/Application Support/Code/User/settings.json"),
                resourceValues: oldValues
            )
        )

        XCTAssertFalse(
            rule.include(
                fileURL: URL(fileURLWithPath: "/Users/test/Library/Application Support/Code/User/workspaceStorage/bookmarks.db"),
                resourceValues: oldValues
            )
        )

        XCTAssertEqual(rule.riskLevel, .review)
    }

    func testJetBrainsReviewRuleIncludesPluginsAndDriversButExcludesStatePaths() {
        let rule = JetBrainsReviewRequiredRule()

        var oldValues = URLResourceValues()
        oldValues.contentModificationDate = Date().addingTimeInterval(-4 * 24 * 60 * 60)

        XCTAssertTrue(
            rule.include(
                fileURL: URL(fileURLWithPath: "/Users/test/Library/Application Support/JetBrains/GoLand2025.1/plugins/pluginA/lib.jar"),
                resourceValues: oldValues
            )
        )

        XCTAssertTrue(
            rule.include(
                fileURL: URL(fileURLWithPath: "/Users/test/Library/Application Support/JetBrains/DataGrip2024.3/jdbc-drivers/driver.zip"),
                resourceValues: oldValues
            )
        )

        XCTAssertFalse(
            rule.include(
                fileURL: URL(fileURLWithPath: "/Users/test/Library/Application Support/JetBrains/DataGrip2024.3/options/editor.xml"),
                resourceValues: oldValues
            )
        )

        XCTAssertFalse(
            rule.include(
                fileURL: URL(fileURLWithPath: "/Users/test/Library/Application Support/JetBrains/GoLand2025.1/workspace.xml"),
                resourceValues: oldValues
            )
        )

        XCTAssertEqual(rule.riskLevel, .review)
    }

    func testDesignerRuleCatalogIncludesPersonaRules() {
        let rules = [any ScanRule].designer
        XCTAssertTrue(rules.contains(where: { $0.id == "designer-caches" }))
        XCTAssertTrue(rules.contains(where: { $0.id == "designer-review-required-media" }))
        XCTAssertTrue(rules.count > [any ScanRule].baseline.count)
    }

    func testVideoBuilderRuleCatalogIncludesPersonaRules() {
        let rules = [any ScanRule].videoBuilder
        XCTAssertTrue(rules.contains(where: { $0.id == "video-builder-caches" }))
        XCTAssertTrue(rules.contains(where: { $0.id == "video-builder-review-required-media" }))
        XCTAssertTrue(rules.count > [any ScanRule].baseline.count)
    }

    func testDesignerRulesRespectPathAndRiskPolicy() {
        let safeRule = DesignerCachesRule()
        let reviewRule = DesignerReviewRequiredMediaRule()

        var oldValues = URLResourceValues()
        oldValues.contentModificationDate = Date().addingTimeInterval(-4 * 24 * 60 * 60)

        XCTAssertTrue(
            safeRule.include(
                fileURL: URL(fileURLWithPath: "/Users/test/Library/Caches/Adobe/Common/cache.bin"),
                resourceValues: oldValues
            )
        )

        XCTAssertTrue(
            reviewRule.include(
                fileURL: URL(fileURLWithPath: "/Users/test/Movies/Adobe Premiere Pro Video Previews/preview.cfa"),
                resourceValues: oldValues
            )
        )

        XCTAssertFalse(
            safeRule.include(
                fileURL: URL(fileURLWithPath: "/Users/test/Library/Application Support/Adobe/Common/Media Cache/bookmarks.db"),
                resourceValues: oldValues
            )
        )

        XCTAssertEqual(safeRule.riskLevel, .safe)
        XCTAssertEqual(reviewRule.riskLevel, .review)
    }

    func testVideoBuilderRulesRespectPathAndRiskPolicy() {
        let safeRule = VideoBuilderCachesRule()
        let reviewRule = VideoBuilderReviewRequiredMediaRule()

        var oldValues = URLResourceValues()
        oldValues.contentModificationDate = Date().addingTimeInterval(-4 * 24 * 60 * 60)

        XCTAssertTrue(
            safeRule.include(
                fileURL: URL(fileURLWithPath: "/Users/test/Library/Application Support/Blackmagic Design/DaVinci Resolve/Cache/media.cache"),
                resourceValues: oldValues
            )
        )

        XCTAssertTrue(
            reviewRule.include(
                fileURL: URL(fileURLWithPath: "/Users/test/Movies/Final Cut Pro Render Files/Library/file.mov"),
                resourceValues: oldValues
            )
        )

        XCTAssertFalse(
            reviewRule.include(
                fileURL: URL(fileURLWithPath: "/Users/test/Documents/Movies/DaVinci Resolve/CacheClip/cacheclip.mov"),
                resourceValues: oldValues
            )
        )

        XCTAssertEqual(safeRule.riskLevel, .safe)
        XCTAssertEqual(reviewRule.riskLevel, .review)
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

    func testScanRunnerCarriesRiskLabelsAndAggregatesAcrossRulesInSameCategory() async {
        let safeDir = URL(fileURLWithPath: "/tmp/designer-safe")
        let reviewDir = URL(fileURLWithPath: "/tmp/designer-review")

        let filesByDirectory = [
            safeDir.path: [
                ScannedFile(url: safeDir.appendingPathComponent("cache.db"), sizeBytes: 150, lastModified: nil)
            ],
            reviewDir.path: [
                ScannedFile(url: reviewDir.appendingPathComponent("preview.cfa"), sizeBytes: 350, lastModified: nil)
            ]
        ]

        let traversal = MockTraversal(filesByDirectory: filesByDirectory)
        let runner = ScanRunner(
            environment: ScanEnvironment(homeDirectory: URL(fileURLWithPath: "/Users/test"), tempDirectory: URL(fileURLWithPath: "/tmp")),
            traversal: traversal
        )

        let rules: [any ScanRule] = [
            TestRule(id: "designer-safe", title: "Designer Safe", category: .designerCaches, riskLevel: .safe, targets: [safeDir]),
            TestRule(id: "designer-review", title: "Designer Review", category: .designerCaches, riskLevel: .review, targets: [reviewDir])
        ]

        let report = await runner.run(rules: rules)
        XCTAssertEqual(report.findings.count, 2)

        let riskLevels = Set(report.findings.map(\.riskLevel))
        XCTAssertEqual(riskLevels, Set([.safe, .review]))

        let summary = report.summaries.first(where: { $0.category == .designerCaches })
        XCTAssertEqual(summary?.reclaimableBytes, 500)
        XCTAssertEqual(summary?.fileCount, 2)
    }

    func testDockerLogsReviewRuleIncludesDockerLogPathsOnly() {
        let rule = DockerLogsReviewRequiredRule()
        let values = URLResourceValues()

        XCTAssertTrue(
            rule.include(
                fileURL: URL(fileURLWithPath: "/Users/test/Library/Containers/com.docker.docker/Data/log/host/docker.log"),
                resourceValues: values
            )
        )

        XCTAssertFalse(
            rule.include(
                fileURL: URL(fileURLWithPath: "/Users/test/Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw"),
                resourceValues: values
            )
        )

        XCTAssertFalse(
            rule.include(
                fileURL: URL(fileURLWithPath: "/Users/test/Library/Containers/com.example.app/Data/log/app.log"),
                resourceValues: values
            )
        )

        XCTAssertEqual(rule.riskLevel, .review)
    }

    func testDockerVMDataAdvancedRuleIncludesVMPathsOnly() {
        let rule = DockerVMDataAdvancedRule()
        let values = URLResourceValues()

        XCTAssertTrue(
            rule.include(
                fileURL: URL(fileURLWithPath: "/Users/test/Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw"),
                resourceValues: values
            )
        )

        XCTAssertFalse(
            rule.include(
                fileURL: URL(fileURLWithPath: "/Users/test/Library/Containers/com.docker.docker/Data/log/host/docker.log"),
                resourceValues: values
            )
        )

        XCTAssertFalse(
            rule.include(
                fileURL: URL(fileURLWithPath: "/Users/test/Library/Containers/com.example.app/Data/vms/0/data/disk.raw"),
                resourceValues: values
            )
        )

        XCTAssertEqual(rule.riskLevel, .advanced)
    }
}
