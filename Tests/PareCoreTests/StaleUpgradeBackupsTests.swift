import XCTest
@testable import PareCore

/// Old upgrade/migration backups are offered for review only once the app has written newer data,
/// and the newest backup of each store is always kept.
final class StaleUpgradeBackupsTests: XCTestCase {

    private static let day: TimeInterval = 24 * 60 * 60

    private var home: URL!

    override func setUpWithError() throws {
        // Canonical `/private/var/…` spelling, as directory listings report it.
        home = ScanPolicy.canonicalPathURL(FileManager.default.temporaryDirectory)
            .appending(path: "pare_backups_\(UUID().uuidString)/home")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: home.deletingLastPathComponent())
    }

    // MARK: - Name signal

    func testNameSignalTable() {
        let cases: [(name: String, signal: Bool)] = [
            ("data.db.backup-2026-01-01", true),
            ("store.bak.1.2.3", true),
            ("config-backup-20260101", true),
            ("upgrade-1.4.0", true),
            ("migration-20250101T1200", true),
            ("schema-2.1", true),
            ("backup1700000000000", true),
            ("Backups-2024-05-06", true),
            ("backupper-tool-1.2", false),
            ("bakery-2.0", false),
            ("backup", false),
            ("data-1.2.db", false),
            ("migrations", false),
            ("rollback-1.2", false),
            ("my-backup-notes", false),
            ("backup-v2", false),
        ]
        for testCase in cases {
            XCTAssertEqual(ScanPolicy.hasUpgradeBackupSignal(testCase.name), testCase.signal, testCase.name)
        }
    }

    func testStoreKeyGroupsBackupsOfTheSameStore() {
        XCTAssertEqual(
            ScanPolicy.upgradeBackupStoreKey("data.db.backup-2026-01-01"),
            ScanPolicy.upgradeBackupStoreKey("data.db.backup-2026-02-01")
        )
        XCTAssertEqual(
            ScanPolicy.upgradeBackupStoreKey("config.json.bak.1.2.0"),
            ScanPolicy.upgradeBackupStoreKey("config.json.backup-20260101")
        )
        XCTAssertNotEqual(
            ScanPolicy.upgradeBackupStoreKey("data.db.backup-2026-01-01"),
            ScanPolicy.upgradeBackupStoreKey("cache.db.backup-2026-01-01")
        )
    }

    func testLocationTable() {
        let cases: [(path: String, allowed: Bool)] = [
            ("/Users/u/.toolx/data.db.backup-2026-01-01", true),
            ("/Users/u/.config/toolx/state.bak.1.2", true),
            ("/Users/u/Library/Application Support/Toolx/db.backup-20260101", true),
            ("/Users/u/Library/Application Support/MobileSync/Backup/x.backup-20260101", false),
            ("/Users/u/Library/Application Support/AddressBook/ab.backup-20260101", false),
            ("/Users/u/Library/Application Support/com.apple.foo/x.backup-20260101", false),
            ("/Users/u/.ssh/known_hosts.bak.20260101", false),
            ("/Users/u/.aws/credentials.bak.20260101", false),
            ("/Users/u/Documents/.notes/thesis.backup-2026-01-01", false),
            ("/Users/u/Documents/thesis.backup-2026-01-01", false),
            ("/Users/u/Projects/app/.git/x.backup-1.2", false),
            ("/Users/u/.toolx/history.backup-2026-01-01", false),
        ]
        for testCase in cases {
            XCTAssertEqual(ScanPolicy.isUpgradeBackupLocation(URL(fileURLWithPath: testCase.path)), testCase.allowed, testCase.path)
        }
    }

    // MARK: - Rule

    func testReportsOldBackupButKeepsTheNewest() async throws {
        let store = home.appending(path: ".toolx")
        try make(store.appending(path: "data.db"), modifiedDaysAgo: 0)
        let oldest = try make(store.appending(path: "data.db.backup-2026-01-01"), modifiedDaysAgo: 90)
        let newest = try make(store.appending(path: "data.db.backup-2026-02-01"), modifiedDaysAgo: 60)

        let findings = await scan()

        XCTAssertEqual(findings.map(\.path), [oldest.path])
        XCTAssertFalse(findings.contains { $0.path == newest.path })
        let finding = try XCTUnwrap(findings.first)
        XCTAssertEqual(finding.riskLevel, .review)
        XCTAssertEqual(finding.category, .applications)
        XCTAssertTrue(finding.reason.hasPrefix("Old upgrade backup from "), finding.reason)
        XCTAssertTrue(finding.reason.contains("toolx has written newer data since"), finding.reason)
        XCTAssertTrue(finding.reason.contains("the newest backup is kept"), finding.reason)
    }

    func testApplicationSupportBackupDirectoryIsReported() async throws {
        let app = home.appending(path: "Library/Application Support/Toolx")
        try make(app.appending(path: "Database/current.sqlite"), modifiedDaysAgo: 1)
        let old = try makeDirectory(app.appending(path: "upgrade-1.2.0"), modifiedDaysAgo: 120)
        try makeDirectory(app.appending(path: "upgrade-1.3.0"), modifiedDaysAgo: 40)

        let findings = await scan()

        XCTAssertEqual(findings.map(\.path), [old.path])
        XCTAssertGreaterThan(findings.first?.sizeBytes ?? 0, 0)
    }

    func testRequiresALiveSiblingWrittenAfterTheBackup() async throws {
        let store = home.appending(path: ".toolx")
        try make(store.appending(path: "data.db"), modifiedDaysAgo: 200)
        try make(store.appending(path: "data.db.backup-2026-01-01"), modifiedDaysAgo: 90)
        try make(store.appending(path: "data.db.backup-2026-02-01"), modifiedDaysAgo: 60)
        let onlyBackups = home.appending(path: ".tooly")
        try make(onlyBackups.appending(path: "a.backup-2026-01-01"), modifiedDaysAgo: 90)
        try make(onlyBackups.appending(path: "a.backup-2026-02-01"), modifiedDaysAgo: 60)
        try make(onlyBackups.appending(path: ".DS_Store"), modifiedDaysAgo: 0)

        let findings = await scan()

        XCTAssertTrue(findings.isEmpty, "\(findings.map(\.path))")
    }

    func testBackupsYoungerThanTheAgeGateAreNotReported() async throws {
        let store = home.appending(path: ".toolx")
        try make(store.appending(path: "data.db"), modifiedDaysAgo: 0)
        try make(store.appending(path: "data.db.backup-2026-01-01"), modifiedDaysAgo: 20)
        try make(store.appending(path: "data.db.backup-2026-02-01"), modifiedDaysAgo: 10)

        let findings = await scan()

        XCTAssertTrue(findings.isEmpty, "\(findings.map(\.path))")
    }

    func testRegisteredInUnifiedScan() {
        XCTAssertTrue(RuleCatalog.all.contains { $0.id == StaleUpgradeBackupsRule().id })
    }

    // MARK: - Cleanup re-verification

    func testCleanupReverifiesEveryCondition() async throws {
        let store = home.appending(path: ".toolx")
        let live = try make(store.appending(path: "data.db"), modifiedDaysAgo: 0)
        let oldest = try make(store.appending(path: "data.db.backup-2026-01-01"), modifiedDaysAgo: 90)
        let newest = try make(store.appending(path: "data.db.backup-2026-02-01"), modifiedDaysAgo: 60)
        XCTAssertTrue(ScanPolicy.isReclaimableUpgradeBackup(oldest))
        XCTAssertFalse(ScanPolicy.isReclaimableUpgradeBackup(newest), "the newest backup is never reclaimable")

        let passing = try await cleanDryRun(oldest)
        XCTAssertEqual(passing.succeeded.count, 1, "\(passing.skipped)")

        try setModified(live, daysAgo: 100)
        let staleLive = try await cleanDryRun(oldest)
        XCTAssertTrue(staleLive.succeeded.isEmpty, "live data older than the backup must block cleanup")

        try setModified(live, daysAgo: 0)
        try FileManager.default.removeItem(at: newest)
        let nowNewest = try await cleanDryRun(oldest)
        XCTAssertTrue(nowNewest.succeeded.isEmpty, "the only remaining backup became the newest")
        guard case .some(.unsafePath(_)) = nowNewest.skipped.first?.error else {
            return XCTFail("expected .unsafePath, got \(nowNewest.skipped)")
        }
    }

    func testBackupNamedPathPassesOnlyThroughTheBackupPredicate() async throws {
        // Under Library/Caches (low impact), but young and without a newer live sibling: must fail closed.
        let caches = home.appending(path: "Library/Caches/com.example.tool")
        let cacheBackup = try make(caches.appending(path: "index.backup-2026-01-01"), modifiedDaysAgo: 40)
        XCTAssertTrue(ScanPolicy.isLowImpactPath(cacheBackup))

        let result = try await cleanDryRun(cacheBackup, category: .userCaches, risk: .safe)

        XCTAssertTrue(result.succeeded.isEmpty)
    }

    // MARK: - Helpers

    private func scan() async -> [ScanFinding] {
        await StaleUpgradeBackupsRule().customScan(environment: ScanEnvironment(homeDirectory: home)) ?? []
    }

    private func cleanDryRun(
        _ url: URL,
        category: ScanCategory = .applications,
        risk: RiskLevel = .review
    ) async throws -> CleanupResult {
        let engine = CleanupEngine(
            store: CleanupTransactionStore(directory: home.deletingLastPathComponent().appending(path: "store")),
            projectRootsProvider: { [] },
            exclusionsProvider: { .empty }
        )
        let finding = ScanFinding(
            category: category,
            riskLevel: risk,
            reason: "test",
            path: url.path,
            sizeBytes: 1,
            lastUsed: nil,
            confidence: 1
        )
        return try await engine.clean(findings: [finding], profileName: "test", dryRun: true)
    }

    @discardableResult
    private func make(_ file: URL, modifiedDaysAgo days: Double) throws -> URL {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 0x42, count: 4096).write(to: file)
        try setModified(file, daysAgo: days)
        return URL(fileURLWithPath: file.path)
    }

    @discardableResult
    private func makeDirectory(_ dir: URL, modifiedDaysAgo days: Double) throws -> URL {
        try make(dir.appending(path: "payload.bin"), modifiedDaysAgo: days)
        try setModified(dir, daysAgo: days)
        return URL(fileURLWithPath: dir.path)
    }

    private func setModified(_ url: URL, daysAgo days: Double) throws {
        let date = Date().addingTimeInterval(-days * Self.day)
        try FileManager.default.setAttributes([.modificationDate: date, .creationDate: date], ofItemAtPath: url.path)
    }
}
