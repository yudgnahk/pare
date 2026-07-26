import XCTest
@testable import PareCore

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
        let rules = RuleCatalog.baseline
        XCTAssertEqual(rules.count, 11, "Baseline includes core + Phase 5–8 additions")
        XCTAssertTrue(rules.contains(where: { $0.id == "user-caches" }))
        XCTAssertTrue(rules.contains(where: { $0.id == "temporary-files" }))
        XCTAssertTrue(rules.contains(where: { $0.id == "logs-crash-reports" }))
        XCTAssertTrue(rules.contains(where: { $0.id == "browser-caches" }))
        XCTAssertTrue(rules.contains(where: { $0.id == "browser-extended-artifacts" }))
        XCTAssertTrue(rules.contains(where: { $0.id == "browser-review-data" }))
        XCTAssertTrue(rules.contains(where: { $0.id == "installer-files" }))
        XCTAssertTrue(rules.contains(where: { $0.id == "stale-app-version" }))
        XCTAssertFalse(rules.contains(where: { $0.id == "project-artifacts" }),
                       "Phase 5 project-artifacts was removed in R0.5 (double-counted with v2)")
        XCTAssertTrue(rules.contains(where: { $0.id == "mobile-sync-backups" }))
        XCTAssertTrue(rules.contains(where: { $0.id == "productivity-caches" }))
        XCTAssertTrue(rules.contains(where: { $0.id == "orphaned-launch-agents" }))
    }

    func testUnifiedCatalogRuleCount() {
        let all = RuleCatalog.all
        let ids = all.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count, "RuleCatalog.all must be unique by id")
        // Keep in sync with RuleCatalog constructors (developer ∪ designer ∪ videoBuilder).
        XCTAssertEqual(all.count, 35, "Update this when adding/removing rules from RuleCatalog")
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

        // R1.4 regression: the rule now uses ScanPolicy's full sensitive-marker
        // set — the old inline copy missed session/cookies/keychain.
        for sensitive in ["Session Cache", "Cookies Cache", "keychain-cache"] {
            XCTAssertFalse(
                rule.include(
                    fileURL: URL(fileURLWithPath: "/Users/test/Library/Caches/Google/Chrome/Default/\(sensitive)/data"),
                    resourceValues: values
                ),
                "\(sensitive) must be blocked by the sensitive-data policy"
            )
        }
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
        let rules = RuleCatalog.developer
        XCTAssertTrue(rules.contains(where: { $0.id == "xcode-derived-data" }))
        XCTAssertTrue(rules.contains(where: { $0.id == "xcode-archives" }))
        XCTAssertTrue(rules.contains(where: { $0.id == "package-manager-caches" }))
        XCTAssertTrue(rules.contains(where: { $0.id == "xcode-simulator-caches" }))
        XCTAssertTrue(rules.contains(where: { $0.id == "vscode-caches" }))
        XCTAssertTrue(rules.contains(where: { $0.id == "vscode-duplicate-extensions" }))
        XCTAssertTrue(rules.contains(where: { $0.id == "vscode-review-required-state" }))
        XCTAssertTrue(rules.contains(where: { $0.id == "jetbrains-safe-caches" }))
        XCTAssertTrue(rules.contains(where: { $0.id == "jetbrains-stale-version" }))
        XCTAssertTrue(rules.contains(where: { $0.id == "jetbrains-review-required" }))
        XCTAssertTrue(rules.contains(where: { $0.id == "docker-storage" }))
        XCTAssertTrue(rules.contains(where: { $0.id == "ai-tool-caches" }))
        XCTAssertTrue(rules.contains(where: { $0.id == "homebrew-cache" }))
        XCTAssertTrue(rules.contains(where: { $0.id == "project-artifacts-v2" }))
        XCTAssertFalse(rules.contains(where: { $0.id == "docker-vm-data-advanced" }))
        // Orphaned logs-only rule is not registered; DockerStorageRule covers logs + VM visibility.
        XCTAssertFalse(rules.contains(where: { $0.id == "docker-logs-review-required" }))
        XCTAssertTrue(rules.count > RuleCatalog.baseline.count)
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

        // Installed extensions are live installs — not review-state paths (duplicates handled elsewhere).
        XCTAssertFalse(
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
        let rules = RuleCatalog.designer
        XCTAssertTrue(rules.contains(where: { $0.id == "designer-caches" }))
        XCTAssertTrue(rules.contains(where: { $0.id == "designer-review-required-media" }))
        XCTAssertTrue(rules.count > RuleCatalog.baseline.count)
    }

    func testVideoBuilderRuleCatalogIncludesPersonaRules() {
        let rules = RuleCatalog.videoBuilder
        XCTAssertTrue(rules.contains(where: { $0.id == "video-builder-caches" }))
        XCTAssertTrue(rules.contains(where: { $0.id == "video-builder-review-required-media" }))
        XCTAssertTrue(rules.count > RuleCatalog.baseline.count)
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

    func testAdvancedFindingsAreExcludedFromReclaimableTotals() async {
        let safeDir = URL(fileURLWithPath: "/tmp/safe-cache")
        let advancedDir = URL(fileURLWithPath: "/tmp/advanced-vm")

        let filesByDirectory = [
            safeDir.path: [
                ScannedFile(url: safeDir.appendingPathComponent("a.cache"), sizeBytes: 100, lastModified: nil)
            ],
            advancedDir.path: [
                ScannedFile(url: advancedDir.appendingPathComponent("Docker.raw"), sizeBytes: 1_099_511_627_776, lastModified: nil)
            ]
        ]

        let traversal = MockTraversal(filesByDirectory: filesByDirectory)
        let runner = ScanRunner(
            environment: ScanEnvironment(homeDirectory: URL(fileURLWithPath: "/Users/test"), tempDirectory: URL(fileURLWithPath: "/tmp")),
            traversal: traversal
        )

        let rules: [any ScanRule] = [
            TestRule(id: "safe", title: "Safe", category: .userCaches, riskLevel: .safe, targets: [safeDir]),
            TestRule(id: "advanced", title: "Advanced", category: .developerPackageCaches, riskLevel: .advanced, targets: [advancedDir])
        ]

        let report = await runner.run(rules: rules)
        XCTAssertEqual(report.findings.count, 2, "Advanced findings must still appear in findings")
        XCTAssertEqual(report.findings.filter { $0.riskLevel == .advanced }.count, 1)
        XCTAssertEqual(report.totalReclaimableBytes, 100, "Advanced sizes must not inflate reclaimable total")
        XCTAssertNil(
            report.summaries.first(where: { $0.category == .developerPackageCaches }),
            "Category with only advanced findings should not appear in reclaimable summaries"
        )
        XCTAssertEqual(
            report.summaries.first(where: { $0.category == .userCaches })?.reclaimableBytes,
            100
        )
    }

    // MARK: - R1.2: per-rule error channel

    private struct ThrowingRule: ScanRule {
        struct Boom: LocalizedError {
            var errorDescription: String? { "boom" }
        }
        let id = "throwing-rule"
        let title = "Throwing Rule"
        let reason = "Always fails"
        let category: ScanCategory = .userCaches
        let riskLevel: RiskLevel = .safe
        let confidence = 1.0

        func targetDirectories(environment: ScanEnvironment) -> [URL] { [] }
        func include(fileURL: URL, resourceValues: URLResourceValues) -> Bool { false }
        func customScanThrowing(environment: ScanEnvironment) async throws -> [ScanFinding]? {
            throw Boom()
        }
    }

    func testRuleFailureIsReportedAndOtherRulesStillRun() async {
        let cacheDir = URL(fileURLWithPath: "/tmp/cache")
        let traversal = MockTraversal(filesByDirectory: [
            cacheDir.path: [
                ScannedFile(url: cacheDir.appendingPathComponent("a.cache"), sizeBytes: 100, lastModified: nil)
            ]
        ])
        let runner = ScanRunner(
            environment: ScanEnvironment(homeDirectory: URL(fileURLWithPath: "/Users/test")),
            traversal: traversal
        )
        let rules: [any ScanRule] = [
            ThrowingRule(),
            TestRule(id: "cache", title: "Cache", category: .userCaches, targets: [cacheDir])
        ]

        let report = await runner.run(rules: rules)

        XCTAssertEqual(report.ruleFailures.count, 1, "rule failed must be reported, not masked")
        XCTAssertEqual(report.ruleFailures.first?.ruleID, "throwing-rule")
        XCTAssertEqual(report.ruleFailures.first?.message, "boom")
        XCTAssertEqual(report.findings.count, 1, "other rules must still contribute findings")
    }

    // MARK: - R1.3: unreadable locations surface on the report

    func testTraversalReportsUnreadableDirectory() async throws {
        let tmp = FileManager.default.temporaryDirectory
            .appending(path: "pare_unreadable_\(UUID().uuidString)")
        let locked = tmp.appending(path: "locked")
        try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: true)
        try Data(repeating: 0x1, count: 16).write(to: locked.appending(path: "hidden-from-scan.bin"))
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path)
            try? FileManager.default.removeItem(at: tmp)
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked.path)

        let result = await FileSystemTraversal().collectFilesReportingErrors(in: [tmp])

        XCTAssertTrue(
            result.unreadablePaths.contains { $0.hasSuffix("locked") },
            "permission-denied directory must be reported, got: \(result.unreadablePaths)"
        )
    }

    func testUnreadableRootDirectoryIsReported() async throws {
        let tmp = FileManager.default.temporaryDirectory
            .appending(path: "pare_unreadable_root_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tmp.path)
            try? FileManager.default.removeItem(at: tmp)
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: tmp.path)

        let result = await FileSystemTraversal().collectFilesReportingErrors(in: [tmp])

        XCTAssertEqual(result.unreadablePaths, [tmp.path])
        XCTAssertTrue(result.files.isEmpty)
    }
}
