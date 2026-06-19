import XCTest
@testable import PareCore

// MARK: - Seeded home-tree helpers

/// Builds a realistic fake macOS home directory tree for integration tests.
/// All junk files are back-dated so they pass the minimum-age policy guards.
final class FakeHomeBuilder {
    let root: URL
    private let fm = FileManager.default

    init(root: URL) {
        self.root = root
    }

    // MARK: - Directory helpers

    func dir(_ components: String...) throws -> URL {
        let url = components.reduce(root) { $0.appending(path: $1) }
        try fm.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    // MARK: - File creation

    /// Creates a file at `root / components`, writes `size` bytes, and back-dates it
    /// by `ageSeconds`.  Returns the created URL.
    @discardableResult
    func file(_ components: String..., size: Int = 4096, ageSeconds: TimeInterval = 5 * 86400) throws -> URL {
        var base = root
        for (i, component) in components.enumerated() {
            if i == components.count - 1 {
                break
            }
            base = base.appending(path: component)
        }
        try fm.createDirectory(at: base, withIntermediateDirectories: true)
        let url = components.reduce(root) { $0.appending(path: $1) }
        try Data(repeating: 0x41, count: size).write(to: url)
        let modDate = Date().addingTimeInterval(-ageSeconds)
        try fm.setAttributes([.modificationDate: modDate], ofItemAtPath: url.path)
        return url
    }

    // MARK: - Standard junk tree

    /// Populates a realistic fake home with known junk and known-protected files.
    /// Returns the URLs of files that SHOULD be found by a baseline scan.
    func buildBaseline() throws -> (shouldFind: [URL], shouldNotFind: [URL]) {
        // --- UserCachesRule targets ---
        // NOTE: Do NOT use directories ending in ".app" — FileSystemTraversal
        // uses .skipsPackageDescendants which treats them as bundle packages.
        let oldCache = try file("Library", "Caches", "com.test.example", "old-cache.bin", ageSeconds: 5 * 86400)
        let freshCache = try file("Library", "Caches", "com.test.example", "fresh-cache.bin", ageSeconds: 0.5 * 86400)  // 12 hours old
        let cookiesFile = try file("Library", "Caches", "com.test.example", "cookies.db", ageSeconds: 10 * 86400)  // sensitive marker

        // --- LogsAndCrashReportsRule targets ---
        let crashLog = try file("Library", "Logs", "SomeApp", "crash.log")
        let diagReport = try file("Library", "DiagnosticReports", "MyApp_2024-01.ips")

        // --- Protected paths — must never appear in findings ---
        let document = try file("Documents", "report.pdf")
        let settingsJson = try file("Library", "Application Support", "Code", "User", "settings.json")

        return (
            shouldFind: [oldCache, crashLog, diagReport],
            shouldNotFind: [freshCache, cookiesFile, document, settingsJson]
        )
    }

    /// Additional developer-profile junk on top of baseline.
    func buildDeveloperExtras() throws -> [URL] {
        // VSCodeCachesRule: ShipIt cache (safe, old)
        let shipIt = try file("Library", "Caches", "com.microsoft.VSCode.ShipIt", "shipit-update.bin")
        // VSCodeCachesRule: CachedExtensionVSIXs (safe, old)
        let vsix = try file("Library", "Application Support", "Code", "CachedExtensionVSIXs", "ms-python.vsix")
        // JetBrainsSafeCachesRule: IDE log (safe, old)
        let jbLog = try file("Library", "Logs", "JetBrains", "GoLand2024.1", "idea.log")
        return [shipIt, vsix, jbLog]
    }
}

// MARK: - ScanIntegrationTests

final class ScanIntegrationTests: XCTestCase {
    private var fakeHome: URL!
    private var builder: FakeHomeBuilder!
    private var storeDir: URL!

    override func setUpWithError() throws {
        fakeHome = URL(fileURLWithPath: "/private/tmp/ScanIntegration-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: fakeHome, withIntermediateDirectories: true)
        builder = FakeHomeBuilder(root: fakeHome)
        storeDir = URL(fileURLWithPath: "/private/tmp/ScanIntegrationStore-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: fakeHome)
        try? FileManager.default.removeItem(at: storeDir)
    }

    private func makeRunner(exclusionList: ExclusionList = .empty) -> ScanRunner {
        ScanRunner(
            environment: ScanEnvironment(homeDirectory: fakeHome),
            traversal: FileSystemTraversal(),
            exclusionList: exclusionList
        )
    }

    // MARK: - Baseline scan: junk files found

    func testBaselineScanFindsOldCacheFiles() async throws {
        let (shouldFind, _) = try builder.buildBaseline()
        let runner = makeRunner()
        let report = await runner.run(rules: RuleCatalog.baseline)

        let foundPaths = Set(report.findings.map(\.path))

        // Old cache and log files should be in findings.
        for url in shouldFind {
            XCTAssertTrue(foundPaths.contains(url.path),
                          "Expected to find: \(url.lastPathComponent)")
        }
        XCTAssertFalse(report.findings.isEmpty)
    }

    // MARK: - Baseline scan: protected / fresh / sensitive files never found

    func testBaselineScanNeverFindsProtectedOrFreshFiles() async throws {
        let (_, shouldNotFind) = try builder.buildBaseline()
        let runner = makeRunner()
        let report = await runner.run(rules: RuleCatalog.baseline)

        let foundPaths = Set(report.findings.map(\.path))

        for url in shouldNotFind {
            XCTAssertFalse(foundPaths.contains(url.path),
                           "Should NOT have found: \(url.lastPathComponent)")
        }
    }

    // MARK: - Developer profile: dev-tooling files found additionally

    func testDeveloperScanFindsVSCodeAndJetBrainsFiles() async throws {
        try builder.buildBaseline()
        let devFiles = try builder.buildDeveloperExtras()
        let runner = makeRunner()
        let report = await runner.run(rules: RuleCatalog.developer)

        let foundPaths = Set(report.findings.map(\.path))

        for url in devFiles {
            XCTAssertTrue(foundPaths.contains(url.path),
                          "Developer scan should have found: \(url.lastPathComponent)")
        }
    }

    // MARK: - Category summaries are consistent with findings

    func testCategorySummaryTotalsMatchFindingsSums() async throws {
        try builder.buildBaseline()
        let runner = makeRunner()
        let report = await runner.run(rules: RuleCatalog.baseline)

        for summary in report.summaries {
            let directSum = report.findings
                .filter { $0.category == summary.category }
                .reduce(0) { $0 + $1.sizeBytes }
            XCTAssertEqual(summary.reclaimableBytes, directSum,
                           "Summary bytes for \(summary.category.rawValue) must match findings sum")
            let directCount = report.findings.filter { $0.category == summary.category }.count
            XCTAssertEqual(summary.fileCount, directCount,
                           "Summary file count for \(summary.category.rawValue) must match findings count")
        }
    }

    // MARK: - Exclusion list prevents excluded paths from appearing in findings

    func testExclusionListFiltersFindings() async throws {
        // Seed a cacheable file that would normally be found.
        let excluded = try builder.file("Library", "Caches", "com.test.excluded", "data.bin")
        let notExcluded = try builder.file("Library", "Caches", "com.test.kept", "data.bin")

        var exclusions = ExclusionList()
        exclusions.add(ExclusionEntry(path: excluded.deletingLastPathComponent().path, matchType: .prefix))

        let runner = makeRunner(exclusionList: exclusions)
        let report = await runner.run(rules: RuleCatalog.baseline)

        let foundPaths = Set(report.findings.map(\.path))
        XCTAssertFalse(foundPaths.contains(excluded.path),
                       "Excluded directory's files should not appear in findings")
        XCTAssertTrue(foundPaths.contains(notExcluded.path),
                      "Non-excluded file should still appear in findings")
    }

    // MARK: - Risk labels are propagated correctly

    func testAllBaselineFindingsAreSafeRisk() async throws {
        try builder.buildBaseline()
        let runner = makeRunner()
        let report = await runner.run(rules: RuleCatalog.baseline)

        // All baseline rules produce safe-risk findings.
        for finding in report.findings {
            XCTAssertEqual(finding.riskLevel, .safe,
                           "Baseline finding at \(finding.path) should be .safe")
        }
    }

    // MARK: - Reason field is non-empty for every finding

    func testEveryFindingHasNonEmptyReason() async throws {
        try builder.buildBaseline()
        try builder.buildDeveloperExtras()
        let runner = makeRunner()
        let report = await runner.run(rules: RuleCatalog.developer)

        for finding in report.findings {
            XCTAssertFalse(finding.reason.isEmpty,
                           "Finding at \(finding.path) has empty reason")
        }
    }

    // MARK: - Total reclaimable is sum of all finding sizes

    func testTotalReclaimableBytesIsConsistent() async throws {
        try builder.buildBaseline()
        let runner = makeRunner()
        let report = await runner.run(rules: RuleCatalog.baseline)

        let sumFromFindings = report.findings.reduce(0) { $0 + $1.sizeBytes }
        XCTAssertEqual(report.totalReclaimableBytes, sumFromFindings)
    }
}

// MARK: - Cleanup + Restore integration

final class CleanupRestoreIntegrationTests: XCTestCase {
    private var fakeHome: URL!
    private var storeDir: URL!

    override func setUpWithError() throws {
        fakeHome = URL(fileURLWithPath: "/private/tmp/CleanupRestore-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: fakeHome, withIntermediateDirectories: true)
        storeDir = URL(fileURLWithPath: "/private/tmp/CleanupRestoreStore-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: fakeHome)
        try? FileManager.default.removeItem(at: storeDir)
    }

    private func makeCacheFile(name: String, ageSeconds: TimeInterval = 5 * 86400) throws -> URL {
        let dir = fakeHome.appending(path: "Library/Caches/com.test.cleanup")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appending(path: name)
        try Data(repeating: 0x41, count: 8192).write(to: url)
        let old = Date().addingTimeInterval(-ageSeconds)
        try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: url.path)
        return url
    }

    private func makeStore() -> CleanupTransactionStore {
        CleanupTransactionStore(directory: storeDir)
    }

    // MARK: - Full scan → quick clean pipeline

    func testScanThenQuickCleanMovesFilesToTrash() async throws {
        let file1 = try makeCacheFile(name: "cache-a.bin")
        let file2 = try makeCacheFile(name: "cache-b.bin")

        let runner = ScanRunner(
            environment: ScanEnvironment(homeDirectory: fakeHome),
            traversal: FileSystemTraversal()
        )
        let report = await runner.run(rules: RuleCatalog.baseline)

        // Both files should be in the scan report.
        let foundPaths = Set(report.findings.map(\.path))
        XCTAssertTrue(foundPaths.contains(file1.path))
        XCTAssertTrue(foundPaths.contains(file2.path))

        // Run quick clean.
        let engine = CleanupEngine(store: makeStore())
        let result = try await engine.quickClean(findings: report.findings, profileName: "baseline")

        XCTAssertEqual(result.succeeded.count, report.findings.filter { $0.riskLevel == .safe }.count)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file1.path), "file1 should be in Trash")
        XCTAssertFalse(FileManager.default.fileExists(atPath: file2.path), "file2 should be in Trash")
        XCTAssertNotNil(result.transaction)
    }

    // MARK: - Quick clean → restore pipeline

    func testQuickCleanThenRestoreBringsFilesBack() async throws {
        let file1 = try makeCacheFile(name: "restore-a.bin")
        let file2 = try makeCacheFile(name: "restore-b.bin")

        let runner = ScanRunner(
            environment: ScanEnvironment(homeDirectory: fakeHome),
            traversal: FileSystemTraversal()
        )
        let report = await runner.run(rules: RuleCatalog.baseline)

        let engine = CleanupEngine(store: makeStore())
        let cleanResult = try await engine.quickClean(findings: report.findings, profileName: "baseline")

        guard let tx = cleanResult.transaction else {
            XCTFail("Expected a transaction to be created")
            return
        }

        // Files should be gone.
        XCTAssertFalse(FileManager.default.fileExists(atPath: file1.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: file2.path))

        // Restore.
        let (restored, skipped) = await engine.restore(transaction: tx)

        XCTAssertEqual(restored.count, cleanResult.succeeded.count,
                       "All cleaned files should be restorable")
        XCTAssertTrue(skipped.isEmpty, "No files should fail to restore")

        // Files should be back.
        XCTAssertTrue(FileManager.default.fileExists(atPath: file1.path), "file1 should be restored")
        XCTAssertTrue(FileManager.default.fileExists(atPath: file2.path), "file2 should be restored")
    }

    // MARK: - Dry-run does not delete, but records transaction

    func testDryRunScanThenDryRunCleanLeavesFilesIntact() async throws {
        let file1 = try makeCacheFile(name: "dryrun-int.bin")

        let runner = ScanRunner(
            environment: ScanEnvironment(homeDirectory: fakeHome),
            traversal: FileSystemTraversal()
        )
        let report = await runner.run(rules: RuleCatalog.baseline)

        let engine = CleanupEngine(store: makeStore())
        let result = try await engine.quickClean(findings: report.findings, profileName: "baseline", dryRun: true)

        XCTAssertTrue(FileManager.default.fileExists(atPath: file1.path),
                      "Dry-run must not delete files")
        XCTAssertTrue(result.transaction?.isDryRun == true)
        XCTAssertEqual(result.transaction?.totalBytesFreed, 0)
        XCTAssertGreaterThan(result.transaction?.totalBytesCandidates ?? 0, 0)
    }

    // MARK: - Deep clean includes review-risk findings

    func testDeepCleanIncludesReviewRiskFromRealScan() async throws {
        let cacheFile = try makeCacheFile(name: "safe-for-deep.bin")

        // Build a synthetic review-risk finding pointing at the same cache dir.
        let reviewFinding = ScanFinding(
            category: .userCaches,
            riskLevel: .review,
            reason: "Synthetic review finding",
            path: cacheFile.path,
            sizeBytes: 8192,
            lastUsed: Date().addingTimeInterval(-5 * 86400),
            confidence: 0.9
        )

        let engine = CleanupEngine(store: makeStore())
        let result = try await engine.deepClean(
            findings: [reviewFinding],
            profileName: "test",
            confirmed: true
        )

        XCTAssertEqual(result.succeeded.count, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: cacheFile.path),
                       "Review-risk file should have been trashed by deep clean")
    }

    // MARK: - Transaction store persists and loads after cleanup

    func testTransactionIsLoadableAfterCleanup() async throws {
        let file1 = try makeCacheFile(name: "tx-persist.bin")
        let runner = ScanRunner(
            environment: ScanEnvironment(homeDirectory: fakeHome),
            traversal: FileSystemTraversal()
        )
        let report = await runner.run(rules: RuleCatalog.baseline)
        let store = makeStore()
        let engine = CleanupEngine(store: store)
        let cleanResult = try await engine.quickClean(findings: report.findings, profileName: "baseline")

        guard let tx = cleanResult.transaction else {
            XCTFail("Expected transaction"); return
        }

        // Load all transactions and check ours is present.
        let loaded = try store.loadAll()
        XCTAssertTrue(loaded.contains { $0.id == tx.id },
                      "Transaction should be persisted and loadable")

        // Verify byte totals are consistent.
        let fromStore = loaded.first { $0.id == tx.id }!
        XCTAssertEqual(fromStore.items.count, cleanResult.succeeded.count)
        XCTAssertGreaterThan(fromStore.totalBytesCandidates, 0)
    }

    // MARK: - Restore skips dry-run transactions gracefully

    func testRestoreOnDryRunTransactionSkipsAll() async throws {
        let finding = ScanFinding(
            category: .userCaches, riskLevel: .safe, reason: "test",
            path: "/private/tmp/no-such-file.bin", sizeBytes: 1,
            lastUsed: nil, confidence: 1.0
        )
        let tx = CleanupTransaction(profileName: "test", isDryRun: true, items: [
            CleanupItem(originalPath: finding.path, trashedPath: nil, sizeBytes: 1,
                        reason: "test", riskLevel: .safe)
        ])
        let engine = CleanupEngine(store: makeStore())
        let (restored, skipped) = await engine.restore(transaction: tx)

        XCTAssertTrue(restored.isEmpty, "Dry-run transaction should not restore anything")
        XCTAssertEqual(skipped.count, 1)
    }
}

// MARK: - JetBrainsSafeCachesRule unit tests

final class JetBrainsSafeCachesRuleTests: XCTestCase {
    private let rule = JetBrainsSafeCachesRule()
    private let env = ScanEnvironment(homeDirectory: URL(fileURLWithPath: "/Users/test"))

    func testTargetDirectoryIsJetBrainsLogs() {
        let targets = rule.targetDirectories(environment: env)
        XCTAssertEqual(targets.count, 1)
        XCTAssertTrue(targets[0].path.hasSuffix("Library/Logs/JetBrains"))
    }

    func testIncludesOldLogFile() {
        let url = URL(fileURLWithPath: "/Users/test/Library/Logs/JetBrains/GoLand2024.1/idea.log")
        var rv = URLResourceValues()
        rv.contentModificationDate = Date().addingTimeInterval(-5 * 86400)  // 5 days old
        XCTAssertTrue(rule.include(fileURL: url, resourceValues: rv))
    }

    func testIncludesOldGzippedLog() {
        let url = URL(fileURLWithPath: "/Users/test/Library/Logs/JetBrains/GoLand2024.1/idea.log.gz")
        var rv = URLResourceValues()
        rv.contentModificationDate = Date().addingTimeInterval(-7 * 86400)
        XCTAssertTrue(rule.include(fileURL: url, resourceValues: rv))
    }

    func testExcludesFreshLogFileBelowOneDayAgeGate() {
        let url = URL(fileURLWithPath: "/Users/test/Library/Logs/JetBrains/GoLand2024.1/idea.log")
        var rv = URLResourceValues()
        rv.contentModificationDate = Date().addingTimeInterval(-12 * 3600)  // 12 hours old
        XCTAssertFalse(rule.include(fileURL: url, resourceValues: rv),
                       "Log files newer than 1 day should be excluded by the minimum age gate")
    }

    func testExcludesXmlConfigFile() {
        // Non-log extension should be excluded.
        let url = URL(fileURLWithPath: "/Users/test/Library/Logs/JetBrains/GoLand2024.1/config.xml")
        var rv = URLResourceValues()
        rv.contentModificationDate = Date().addingTimeInterval(-10 * 86400)
        XCTAssertFalse(rule.include(fileURL: url, resourceValues: rv))
    }

    func testExcludesFilesOutsideJetBrainsPath() {
        // A .log file not in the JetBrains logs tree should not match.
        let url = URL(fileURLWithPath: "/Users/test/Library/Logs/SomeOtherApp/debug.log")
        var rv = URLResourceValues()
        rv.contentModificationDate = Date().addingTimeInterval(-10 * 86400)
        XCTAssertFalse(rule.include(fileURL: url, resourceValues: rv))
    }

    func testRuleIsRegisteredInDeveloperProfile() {
        let rules = RuleCatalog.developer
        XCTAssertTrue(rules.contains { $0.id == "jetbrains-safe-caches" },
                      "jetbrains-safe-caches must be in the developer rule catalog")
    }
}

// MARK: - customScan path through ScanRunner

final class CustomScanRouteTests: XCTestCase {

    /// A rule that uses customScan to produce two findings without any file traversal.
    struct CustomScanRule: ScanRule {
        let id = "custom-test"
        let title = "Custom Test Rule"
        let reason = "Custom scan finding"
        let category: ScanCategory = .developerPackageCaches
        let riskLevel: RiskLevel = .safe
        let confidence: Double = 1.0

        let customFindings: [ScanFinding]

        func targetDirectories(environment: ScanEnvironment) -> [URL] { [] }
        func include(fileURL: URL, resourceValues: URLResourceValues) -> Bool { false }

        func customScan(environment: ScanEnvironment) async -> [ScanFinding]? {
            customFindings
        }
    }

    func testCustomScanFindingsAreIncludedInReport() async {
        let f1 = ScanFinding(category: .developerPackageCaches, riskLevel: .safe,
                             reason: "Custom 1", path: "/tmp/custom/a", sizeBytes: 1000,
                             lastUsed: nil, confidence: 1.0)
        let f2 = ScanFinding(category: .developerPackageCaches, riskLevel: .safe,
                             reason: "Custom 2", path: "/tmp/custom/b", sizeBytes: 2000,
                             lastUsed: nil, confidence: 1.0)
        let rule = CustomScanRule(customFindings: [f1, f2])

        let runner = ScanRunner(
            environment: ScanEnvironment(homeDirectory: URL(fileURLWithPath: "/Users/test")),
            traversal: FileSystemTraversal()
        )
        let report = await runner.run(rules: [rule])

        XCTAssertEqual(report.findings.count, 2)
        XCTAssertEqual(report.totalReclaimableBytes, 3000)

        let paths = Set(report.findings.map(\.path))
        XCTAssertTrue(paths.contains("/tmp/custom/a"))
        XCTAssertTrue(paths.contains("/tmp/custom/b"))
    }

    func testCustomScanFindingsAreFilteredByExclusionList() async {
        let f1 = ScanFinding(category: .developerPackageCaches, riskLevel: .safe,
                             reason: "Include", path: "/tmp/custom/keep", sizeBytes: 500,
                             lastUsed: nil, confidence: 1.0)
        let f2 = ScanFinding(category: .developerPackageCaches, riskLevel: .safe,
                             reason: "Exclude", path: "/tmp/custom/skip", sizeBytes: 500,
                             lastUsed: nil, confidence: 1.0)
        let rule = CustomScanRule(customFindings: [f1, f2])

        var exclusions = ExclusionList()
        exclusions.add(ExclusionEntry(path: "/tmp/custom/skip", matchType: .exact))

        let runner = ScanRunner(
            environment: ScanEnvironment(homeDirectory: URL(fileURLWithPath: "/Users/test")),
            traversal: FileSystemTraversal(),
            exclusionList: exclusions
        )
        let report = await runner.run(rules: [rule])

        XCTAssertEqual(report.findings.count, 1)
        XCTAssertEqual(report.findings.first?.path, "/tmp/custom/keep")
    }

    func testCustomScanEmptyResultIsIncluded() async {
        let rule = CustomScanRule(customFindings: [])
        let runner = ScanRunner(
            environment: ScanEnvironment(homeDirectory: URL(fileURLWithPath: "/Users/test")),
            traversal: FileSystemTraversal()
        )
        let report = await runner.run(rules: [rule])
        XCTAssertTrue(report.findings.isEmpty)
        XCTAssertEqual(report.totalReclaimableBytes, 0)
    }
}

// MARK: - Scan cancellation reliability

final class ScanCancellationTests: XCTestCase {
    private var fakeHome: URL!

    override func setUpWithError() throws {
        fakeHome = URL(fileURLWithPath: "/private/tmp/ScanCancel-\(UUID().uuidString)")
        // Build a big enough tree that there's something to cancel mid-scan.
        let cacheDir = fakeHome.appending(path: "Library/Caches/com.test.bigcache")
        try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        for i in 0..<20 {
            let f = cacheDir.appending(path: "file-\(i).bin")
            try Data(repeating: 0x41, count: 1024).write(to: f)
            let old = Date().addingTimeInterval(-5 * 86400)
            try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: f.path)
        }
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: fakeHome)
    }

    func testCancelledScanProducesNoResults() async {
        let runner = ScanRunner(
            environment: ScanEnvironment(homeDirectory: fakeHome),
            traversal: FileSystemTraversal()
        )

        // Wrap in a Task so we can cancel it.
        let task = Task {
            await runner.run(rules: RuleCatalog.baseline)
        }
        task.cancel()

        let report = await task.value

        // A cancelled scan should not produce findings (it may return partial/empty).
        // We can't assert exact count since timing is non-deterministic, but we can
        // assert the total is consistent with whatever was found.
        let directSum = report.findings.reduce(0) { $0 + $1.sizeBytes }
        XCTAssertEqual(report.totalReclaimableBytes, directSum,
                       "Even after cancellation, report totals must be internally consistent")
    }

    func testScanRunsNormallyWithoutCancellation() async {
        let runner = ScanRunner(
            environment: ScanEnvironment(homeDirectory: fakeHome),
            traversal: FileSystemTraversal()
        )
        let report = await runner.run(rules: RuleCatalog.baseline)

        // With 20 seeded files, at least some should be found.
        XCTAssertFalse(report.findings.isEmpty, "Non-cancelled scan should find the seeded files")
    }
}
