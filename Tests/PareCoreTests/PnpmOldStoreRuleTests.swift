import XCTest
@testable import PareCore

/// Old pnpm store versions next to the one pnpm actually uses: offered for review, never the active one.
final class PnpmOldStoreRuleTests: XCTestCase {

    private var home: URL!
    private var store: URL { home.appending(path: "Library/pnpm/store") }

    override func setUpWithError() throws {
        // Canonical `/private/var/…` spelling, as directory listings report it.
        home = ScanPolicy.canonicalPathURL(FileManager.default.temporaryDirectory)
            .appending(path: "pare_pnpm_\(UUID().uuidString)/home")
        for name in ["v3", "v10", "v11", "tmp", "v12-beta", "v10.1"] {
            let dir = store.appending(path: name)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try Data(repeating: 0x42, count: 4096).write(to: dir.appending(path: "index.json"))
            // Past the cache age gate CleanupEngine applies to developer package caches.
            let old = Date().addingTimeInterval(-30 * 24 * 60 * 60)
            try FileManager.default.setAttributes([.modificationDate: old, .creationDate: old], ofItemAtPath: dir.path)
        }
        try Data().write(to: store.appending(path: "v2"))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: home.deletingLastPathComponent())
    }

    // MARK: - Parsing

    func testStoreVersionParseTable() {
        let cases: [(name: String, version: Int?)] = [
            ("v3", 3), ("v10", 10), ("v11", 11), ("v0", 0),
            ("v10.1", nil), ("v12-beta", nil), ("V10", nil), ("v", nil), ("10", nil), ("tmp", nil), ("v1a", nil),
        ]
        for testCase in cases {
            XCTAssertEqual(ScanPolicy.pnpmStoreVersion(testCase.name), testCase.version, testCase.name)
        }
    }

    func testActiveStoreFromPnpmStorePathOutput() {
        let cases: [(output: String?, path: String?)] = [
            ("/Users/u/Library/pnpm/store/v10\n", "/Users/u/Library/pnpm/store/v10"),
            ("  /Users/u/.local/share/pnpm/store/v3  ", "/Users/u/.local/share/pnpm/store/v3"),
            ("WARN something\n/Users/u/Library/pnpm/store/v11\n", "/Users/u/Library/pnpm/store/v11"),
            ("/Users/u/Library/pnpm/store", nil),
            ("relative/store/v10", nil),
            ("", nil),
            (nil, nil),
        ]
        for testCase in cases {
            XCTAssertEqual(PnpmStoreLocator.activeStore(fromStorePathOutput: testCase.output)?.path, testCase.path,
                           String(describing: testCase.output))
        }
    }

    // MARK: - Rule

    func testReportsOnlyLowerVersionsInTheActiveStoreRoot() async throws {
        let findings = await rule(active: store.appending(path: "v11")).customScan(environment: ScanEnvironment(homeDirectory: home)) ?? []

        XCTAssertEqual(Set(findings.map(\.path)), [store.appending(path: "v3").path, store.appending(path: "v10").path])
        let v10 = try XCTUnwrap(findings.first { $0.path.hasSuffix("/v10") })
        XCTAssertEqual(v10.riskLevel, .review)
        XCTAssertEqual(v10.category, .developerPackageCaches)
        XCTAssertEqual(v10.reason, "Old pnpm store v10 — pnpm now uses v11; projects reinstall from the new store")
        XCTAssertGreaterThan(v10.sizeBytes, 0)
    }

    func testNothingWhenTheActiveVersionIsUnknown() async {
        let absent = await rule(active: nil).customScan(environment: ScanEnvironment(homeDirectory: home)) ?? []
        XCTAssertTrue(absent.isEmpty, "pnpm absent or silent: fail closed")
    }

    func testOtherStoreRootsAreNotTouched() async throws {
        let elsewhere = home.appending(path: ".local/share/pnpm/store")
        try FileManager.default.createDirectory(at: elsewhere.appending(path: "v1"), withIntermediateDirectories: true)
        try Data(repeating: 0x42, count: 4096).write(to: elsewhere.appending(path: "v1/index.json"))

        let findings = await rule(active: elsewhere.appending(path: "v2")).customScan(environment: ScanEnvironment(homeDirectory: home)) ?? []

        XCTAssertEqual(findings.map(\.path), [elsewhere.appending(path: "v1").path], "only siblings of the active store")
    }

    func testRegisteredInUnifiedScan() {
        XCTAssertTrue(RuleCatalog.all.contains { $0.id == PnpmOldStoreRule().id })
    }

    // MARK: - Cleanup re-verification

    func testReclaimablePredicate() {
        let active = store.appending(path: "v11")
        XCTAssertTrue(ScanPolicy.isReclaimableOldPnpmStore(store.appending(path: "v10"), activeStore: active))
        XCTAssertFalse(ScanPolicy.isReclaimableOldPnpmStore(active, activeStore: active), "never the active store")
        XCTAssertFalse(ScanPolicy.isReclaimableOldPnpmStore(store.appending(path: "v12-beta"), activeStore: active))
        XCTAssertFalse(ScanPolicy.isReclaimableOldPnpmStore(store.appending(path: "v10"), activeStore: nil), "unknown active: fail closed")
        XCTAssertFalse(ScanPolicy.isReclaimableOldPnpmStore(store.appending(path: "v10"), activeStore: store.appending(path: "v3")),
                       "a newer version than the active one is not old")
        XCTAssertFalse(ScanPolicy.isReclaimableOldPnpmStore(
            home.appending(path: ".local/share/pnpm/store/v1"), activeStore: active), "different store root")
    }

    func testCleanupRefusesActiveAndUnverifiableStoresDespiteTheBroadPnpmMarker() async throws {
        let active = store.appending(path: "v11")
        let old = store.appending(path: "v10")

        let verified = try await cleanDryRun([old, active], activeStore: active)
        XCTAssertEqual(verified.succeeded.map(\.originalPath), [old.path])
        XCTAssertEqual(verified.skipped.map(\.path), [active.path])

        let unknown = try await cleanDryRun([old], activeStore: nil)
        XCTAssertTrue(unknown.succeeded.isEmpty, "store versions pass only when the active version is known")
    }

    func testCleanupRefusesTheActiveStoreTreeStoreRootAndPnpmHome() async throws {
        let active = store.appending(path: "v11")
        let insideActive = active.appending(path: "index.json")
        let pnpmHome = home.appending(path: "Library/pnpm")
        let recased = URL(fileURLWithPath: home.path + "/Library/PNPM/Store/v11")
        for url in [active, insideActive, store, pnpmHome, recased] {
            XCTAssertTrue(ScanPolicy.isPnpmGuardedPath(url), url.path)
        }

        let result = try await cleanDryRun([active, insideActive, store, pnpmHome, recased], activeStore: active)

        XCTAssertTrue(result.succeeded.isEmpty, "\(result.succeeded.map(\.originalPath))")
        XCTAssertEqual(result.skipped.count, 5)
        XCTAssertFalse(ScanPolicy.isPnpmGuardedPath(home.appending(path: "Library/Caches/pnpm")), "the download cache is not a store")
    }

    // MARK: - Helpers

    private func rule(active: URL?) -> PnpmOldStoreRule {
        PnpmOldStoreRule(activeStore: { _ in active })
    }

    private func cleanDryRun(_ urls: [URL], activeStore: URL?) async throws -> CleanupResult {
        let engine = CleanupEngineFixture.make(
            store: CleanupTransactionStore(directory: home.deletingLastPathComponent().appending(path: "transactions")),
            projectRootsProvider: { [] },
            exclusionsProvider: { .empty },
            pnpmActiveStore: { activeStore }
        )
        let findings = urls.map {
            ScanFinding(category: .developerPackageCaches, riskLevel: .review, reason: "test", path: $0.path,
                        sizeBytes: 1, lastUsed: nil, confidence: 1)
        }
        return try await engine.clean(findings: findings, profileName: "test", dryRun: true)
    }
}
