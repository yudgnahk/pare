import XCTest
@testable import App BCore

final class CleanupEngineTests: XCTestCase {

    // MARK: - Helpers

    private var tempDir: URL!
    private var storeDir: URL!

    override func setUpWithError() throws {
        // Place test files under a path that contains "/Library/Caches/" so
        // ScanPolicy.isLowImpactPath returns true and the CleanupEngine policy
        // guard doesn't skip them during tests.
        let base = URL(fileURLWithPath: "/private/tmp/CleanupEngineTests-\(UUID().uuidString)")
        tempDir = base.appending(path: "Library/Caches/com.yudgnahk.pare.test")
        storeDir = URL(fileURLWithPath: "/private/tmp/CleanupEngineStore-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        // Remove the top-level test root (two levels above tempDir).
        let testRoot = tempDir.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        try? FileManager.default.removeItem(at: testRoot)
        try? FileManager.default.removeItem(at: storeDir)
    }

    /// Creates a real file under a `/Library/Caches/` path so `ScanPolicy.isLowImpactPath`
    /// accepts it, and returns the matching `ScanFinding`.
    private func makeTempFile(
        name: String,
        sizeBytes: Int64 = 1024,
        ageSeconds: TimeInterval = 5 * 24 * 60 * 60,
        riskLevel: RiskLevel = .safe,
        category: ScanCategory = .userCaches,
        reason: String = "Test cache file"
    ) throws -> (url: URL, finding: ScanFinding) {
        let url = tempDir.appendingPathComponent(name)
        let data = Data(repeating: 0x41, count: Int(sizeBytes))
        try data.write(to: url)

        // Back-date the file modification time.
        let oldDate = Date().addingTimeInterval(-ageSeconds)
        try FileManager.default.setAttributes(
            [.modificationDate: oldDate],
            ofItemAtPath: url.path
        )

        let finding = ScanFinding(
            category: category,
            riskLevel: riskLevel,
            reason: reason,
            path: url.path,
            sizeBytes: sizeBytes,
            lastUsed: oldDate,
            confidence: 0.95
        )
        return (url, finding)
    }

    private func makeStore() -> CleanupTransactionStore {
        CleanupTransactionStore(directory: storeDir)
    }

    // MARK: - CleanupEngine: safe path moves to Trash

    func testCleanMovesSafeFileToTrash() async throws {
        let (_, finding) = try makeTempFile(name: "safe-cache.bin")
        let engine = CleanupEngine(store: makeStore())

        let result = try await engine.clean(findings: [finding], profileName: "test")

        XCTAssertEqual(result.succeeded.count, 1)
        XCTAssertEqual(result.skipped.count, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: finding.path),
                       "File should have been moved to Trash")
    }

    // MARK: - CleanupEngine: ADVANCED risk is always blocked

    func testCleanBlocksAdvancedRiskFindings() async throws {
        let (_, finding) = try makeTempFile(name: "docker.raw", riskLevel: .advanced, reason: "Docker VM disk image")
        let engine = CleanupEngine(store: makeStore())

        let result = try await engine.clean(findings: [finding], profileName: "test")

        XCTAssertEqual(result.succeeded.count, 0)
        XCTAssertEqual(result.skipped.count, 1)
        XCTAssertTrue(result.skipped[0].reason.contains("ADVANCED"))
        // File must still exist on disk.
        XCTAssertTrue(FileManager.default.fileExists(atPath: finding.path))
    }

    // MARK: - CleanupEngine: missing file is skipped gracefully

    func testCleanSkipsMissingFile() async throws {
        let finding = ScanFinding(
            category: .userCaches,
            riskLevel: .safe,
            reason: "Ghost file",
            path: "/tmp/does-not-exist-\(UUID().uuidString).bin",
            sizeBytes: 1024,
            lastUsed: nil,
            confidence: 0.9
        )
        let engine = CleanupEngine(store: makeStore())

        let result = try await engine.clean(findings: [finding], profileName: "test")

        XCTAssertEqual(result.succeeded.count, 0)
        XCTAssertEqual(result.skipped.count, 1)
    }

    // MARK: - Dry-run: no files are moved but transaction is recorded

    func testDryRunDoesNotDeleteFiles() async throws {
        let (_, finding) = try makeTempFile(name: "dryrun-cache.bin")
        let engine = CleanupEngine(store: makeStore())

        let result = try await engine.clean(findings: [finding], profileName: "test", dryRun: true)

        XCTAssertEqual(result.succeeded.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: finding.path),
                      "Dry-run must not delete files")
        XCTAssertTrue(result.transaction?.isDryRun == true)
        // Dry-run items have no trashedPath.
        XCTAssertNil(result.succeeded.first?.trashedPath)
    }

    func testDryRunTotalBytesFreedIsZero() async throws {
        let (_, finding) = try makeTempFile(name: "dryrun2.bin", sizeBytes: 2048)
        let engine = CleanupEngine(store: makeStore())

        let result = try await engine.clean(findings: [finding], profileName: "test", dryRun: true)

        XCTAssertEqual(result.transaction?.totalBytesFreed, 0)
        XCTAssertEqual(result.transaction?.totalBytesCandidates, 2048)
    }

    // MARK: - Quick Clean: only safe-risk findings are processed

    func testQuickCleanFiltersToSafeOnly() async throws {
        let (_, safeFile) = try makeTempFile(name: "qc-safe.bin", riskLevel: .safe)
        let (_, reviewFile) = try makeTempFile(name: "qc-review.bin", riskLevel: .review)
        let (_, advancedFile) = try makeTempFile(name: "qc-advanced.bin", riskLevel: .advanced)
        let engine = CleanupEngine(store: makeStore())

        let result = try await engine.quickClean(
            findings: [safeFile, reviewFile, advancedFile],
            profileName: "test",
            dryRun: true
        )

        // Only the safe finding is in the dry-run candidates.
        XCTAssertEqual(result.succeeded.count, 1)
        XCTAssertEqual(result.succeeded.first?.originalPath, safeFile.path)
    }

    // MARK: - Transaction store: persist and reload

    func testTransactionStoreRoundtrip() throws {
        let store = makeStore()
        let item = CleanupItem(
            originalPath: "/Users/test/Library/Caches/foo.bin",
            trashedPath: "~/.Trash/foo.bin",
            sizeBytes: 512,
            reason: "Test cache",
            riskLevel: .safe
        )
        let transaction = CleanupTransaction(profileName: "baseline", isDryRun: false, items: [item])

        try store.save(transaction)

        let loaded = try store.loadAll()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.id, transaction.id)
        XCTAssertEqual(loaded.first?.items.first?.originalPath, item.originalPath)
        XCTAssertEqual(loaded.first?.items.first?.riskLevel, .safe)
    }

    func testTransactionStoreLoadById() throws {
        let store = makeStore()
        let transaction = CleanupTransaction(profileName: "developer", isDryRun: true, items: [])
        try store.save(transaction)

        let loaded = try store.load(id: transaction.id)
        XCTAssertEqual(loaded?.id, transaction.id)
        XCTAssertTrue(loaded?.isDryRun == true)
    }

    func testTransactionStoreReturnsEmptyWhenNoDirectory() throws {
        let store = makeStore()
        let transactions = try store.loadAll()
        XCTAssertTrue(transactions.isEmpty)
    }

    // MARK: - ScanPolicy: app-state sensitive markers are blocked

    func testAppStateSensitiveMarkersAreBlocked() {
        let settingsURL = URL(fileURLWithPath: "/Users/test/Library/Application Support/Code/User/settings.json")
        let gitCredURL = URL(fileURLWithPath: "/Users/test/.git-credentials")
        let sshURL = URL(fileURLWithPath: "/Users/test/.ssh/id_rsa")

        XCTAssertFalse(ScanPolicy.isLowImpactPath(settingsURL),
                       "VS Code settings.json must be blocked")
        XCTAssertFalse(ScanPolicy.isLowImpactPath(gitCredURL),
                       ".git-credentials must be blocked")
        XCTAssertFalse(ScanPolicy.isLowImpactPath(sshURL),
                       "SSH keys must be blocked")
    }

    // MARK: - ScanFinding: reason is propagated from rule

    func testScanFindingCarriesReason() async {
        let dir = URL(fileURLWithPath: "/tmp/reason-test")
        let file = dir.appendingPathComponent("file.cache")
        let files = [ScannedFile(url: file, sizeBytes: 100, lastModified: nil)]

        struct FixedRule: ScanRule {
            let id = "reason-rule"
            let title = "Reason Rule"
            let reason = "Test rule reason"
            let category: ScanCategory = .userCaches
            let riskLevel: RiskLevel = .safe
            let confidence: Double = 1.0
            func targetDirectories(environment: ScanEnvironment) -> [URL] { [URL(fileURLWithPath: "/tmp/reason-test")] }
            func include(fileURL: URL, resourceValues: URLResourceValues) -> Bool { true }
        }

        struct FixedTraversal: FileTraversing {
            let files: [ScannedFile]
            func collectFiles(in directories: [URL]) async -> [ScannedFile] { files }
        }

        let runner = ScanRunner(
            environment: ScanEnvironment(homeDirectory: URL(fileURLWithPath: "/Users/test")),
            traversal: FixedTraversal(files: files)
        )
        let report = await runner.run(rules: [FixedRule()])
        XCTAssertEqual(report.findings.first?.reason, "Test rule reason")
    }
}
