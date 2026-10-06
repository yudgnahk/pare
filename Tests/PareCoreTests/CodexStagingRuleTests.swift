import XCTest
@testable import PareCore

/// Abandoned Codex marketplace staging folders: exactly two roots, three prefixes, never backups,
/// older than 30 days, no symlinks, and never while Codex or ChatGPT runs.
final class CodexStagingRuleTests: XCTestCase {

    private static let day: TimeInterval = 24 * 60 * 60

    private var home: URL!

    override func setUpWithError() throws {
        // Canonical `/private/var/…` spelling, as directory listings report it.
        home = ScanPolicy.canonicalPathURL(FileManager.default.temporaryDirectory)
            .appending(path: "pare_codex_\(UUID().uuidString)/home")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: home.deletingLastPathComponent())
    }

    private var bundled: URL { home.appending(path: ".codex/.tmp/bundled-marketplaces") }
    private var staging: URL { home.appending(path: ".codex/.tmp/marketplaces/.staging") }

    // MARK: - Policy

    func testEntryNameTable() {
        let cases: [(name: String, qualifies: Bool)] = [
            ("openai-bundled.staging-3PFuSt", true),
            ("marketplace-upgrade-GVvHgW", true),
            ("marketplace-add-ul7pZw", true),
            ("marketplace-backup-MpS2l6", false),
            ("openai-bundled", false),
            ("claude-plugins-official", false),
            ("marketplace-upgrade", false),
            ("Marketplace-Upgrade-abc", false),
        ]
        for testCase in cases {
            XCTAssertEqual(ScanPolicy.isCodexStagingEntryName(testCase.name), testCase.qualifies, testCase.name)
        }
    }

    func testLocationIsExactlyADirectChildOfAStagingRoot() {
        let cases: [(path: String, allowed: Bool)] = [
            ("/Users/u/.codex/.tmp/bundled-marketplaces/openai-bundled.staging-x", true),
            ("/Users/u/.codex/.tmp/marketplaces/.staging/marketplace-upgrade-x", true),
            ("/Users/u/.codex/.tmp/marketplaces/marketplace-upgrade-x", false),
            ("/Users/u/.codex/.tmp/marketplaces/.staging/nested/marketplace-upgrade-x", false),
            ("/Users/u/.codex/.tmp/git-0KXk47", false),
            ("/Users/u/.codex/.tmp/marketplaces/.staging", false),
            ("/Users/u/Projects/.tmp/bundled-marketplaces/openai-bundled.staging-x", false),
        ]
        for testCase in cases {
            XCTAssertEqual(ScanPolicy.isCodexStagingEntryLocation(URL(fileURLWithPath: testCase.path)), testCase.allowed, testCase.path)
        }
    }

    func testRunningCheckMatchesExactNamesOnly() {
        let cases: [(processes: String?, bundles: [String], running: Bool)] = [
            ("CodexBar\nCodexBarClaudeWatchdog\nFinder", [], false),
            ("Finder\ncodex\n", [], true),
            ("ChatGPT", [], true),
            ("Finder", ["com.openai.chat"], true),
            ("Finder", ["com.openai.codex"], true),
            ("Finder", ["com.example.codexbar"], false),
            (nil, [], true),
        ]
        for testCase in cases {
            XCTAssertEqual(
                CodexActivity.isRunning(processNames: testCase.processes, bundleIdentifiers: testCase.bundles),
                testCase.running,
                "\(String(describing: testCase.processes)) \(testCase.bundles)"
            )
        }
    }

    // MARK: - Rule

    func testReportsOnlyOldQualifyingEntriesIncludingEmptyOnes() async throws {
        let oldUpgrade = try makeDirectory(staging.appending(path: "marketplace-upgrade-old"), daysAgo: 40, payload: true)
        try makeDirectory(staging.appending(path: "marketplace-upgrade-young"), daysAgo: 10, payload: true)
        try makeDirectory(staging.appending(path: "marketplace-backup-keep"), daysAgo: 40, payload: true)
        try makeDirectory(bundled.appending(path: "openai-bundled"), daysAgo: 40, payload: true)
        let emptyStaging = try makeDirectory(bundled.appending(path: "openai-bundled.staging-abc"), daysAgo: 40, payload: false)
        let elsewhere = try makeDirectory(home.appending(path: "elsewhere"), daysAgo: 40, payload: true)
        try FileManager.default.createSymbolicLink(at: staging.appending(path: "marketplace-add-link"), withDestinationURL: elsewhere)

        let findings = await rule(running: false).customScan(environment: ScanEnvironment(homeDirectory: home)) ?? []

        XCTAssertEqual(Set(findings.map(\.path)), [oldUpgrade.path, emptyStaging.path])
        XCTAssertEqual(findings.first { $0.path == emptyStaging.path }?.sizeBytes, 0, "empty staging dirs are still leftovers")
        XCTAssertTrue(findings.allSatisfy { $0.category == .aiToolCaches && $0.riskLevel == .safe })
    }

    func testDefersWhileCodexOrChatGPTRuns() async throws {
        try makeDirectory(staging.appending(path: "marketplace-upgrade-old"), daysAgo: 40, payload: true)

        let findings = await rule(running: true).customScan(environment: ScanEnvironment(homeDirectory: home)) ?? []

        XCTAssertTrue(findings.isEmpty)
    }

    func testFolderRollupShowsOneRowPerRoot() {
        let first = staging.appending(path: "marketplace-upgrade-a").path
        let second = staging.appending(path: "marketplace-add-b").path

        XCTAssertEqual(FolderRollup.rollupFolderPath(for: first), staging.path)
        XCTAssertEqual(FolderRollup.rollupFolderPath(for: second), staging.path)
        XCTAssertEqual(FolderRollup.rollupFolderPath(for: bundled.appending(path: "openai-bundled.staging-c").path), bundled.path)
    }

    func testRegisteredInUnifiedScan() {
        XCTAssertTrue(RuleCatalog.all.contains { $0.id == CodexStagingRule().id })
    }

    // MARK: - Cleanup re-verification

    func testCleanupReverifiesPrefixAgeBackupRunningAndRoot() async throws {
        let old = try makeDirectory(staging.appending(path: "marketplace-upgrade-old"), daysAgo: 40, payload: true)
        let young = try makeDirectory(staging.appending(path: "marketplace-upgrade-young"), daysAgo: 10, payload: true)
        let backup = try makeDirectory(staging.appending(path: "marketplace-backup-keep"), daysAgo: 40, payload: true)
        try setDates(staging, daysAgo: 40)

        let idle = try await cleanDryRun([old, young, backup, staging], codexRunning: false)
        XCTAssertEqual(idle.succeeded.map(\.originalPath), [old.path])
        XCTAssertEqual(Set(idle.skipped.map(\.path)), [young.path, backup.path, staging.path], "the root itself is never trashed")

        let busy = try await cleanDryRun([old], codexRunning: true)
        XCTAssertTrue(busy.succeeded.isEmpty, "never while Codex or ChatGPT runs")
    }

    // MARK: - Helpers

    private func rule(running: Bool) -> CodexStagingRule {
        CodexStagingRule(isCodexRunning: { running })
    }

    private func cleanDryRun(_ urls: [URL], codexRunning: Bool) async throws -> CleanupResult {
        let engine = CleanupEngine(
            store: CleanupTransactionStore(directory: home.deletingLastPathComponent().appending(path: "store")),
            projectRootsProvider: { [] },
            exclusionsProvider: { .empty },
            isCodexRunning: { codexRunning }
        )
        let findings = urls.map {
            ScanFinding(category: .aiToolCaches, riskLevel: .safe, reason: "test", path: $0.path,
                        sizeBytes: 1, lastUsed: nil, confidence: 1)
        }
        return try await engine.clean(findings: findings, profileName: "test", dryRun: true)
    }

    @discardableResult
    private func makeDirectory(_ dir: URL, daysAgo: Double, payload: Bool) throws -> URL {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if payload {
            let file = dir.appending(path: "marketplace.json")
            try Data(repeating: 0x7B, count: 2048).write(to: file)
            try setDates(file, daysAgo: daysAgo)
        }
        try setDates(dir, daysAgo: daysAgo)
        return URL(fileURLWithPath: dir.path)
    }

    private func setDates(_ url: URL, daysAgo: Double) throws {
        let date = Date().addingTimeInterval(-daysAgo * Self.day)
        try FileManager.default.setAttributes([.modificationDate: date, .creationDate: date], ofItemAtPath: url.path)
    }
}
