import XCTest
@testable import PareCore

/// A cleanable folder must never take report-only or never-clean content to the Trash with it.
final class ReportOnlyContainmentTests: XCTestCase {

    private var tmp: URL!
    private var cache: URL!

    override func setUpWithError() throws {
        // `/Library/Caches/` under /private/tmp passes the low-impact policy, as in CleanupEngineTests.
        tmp = URL(fileURLWithPath: "/private/tmp/pare_contain_\(UUID().uuidString)")
        cache = tmp.appending(path: "Library/Caches/com.example.app")
        try FileManager.default.createDirectory(at: cache.appending(path: "inner"), withIntermediateDirectories: true)
        try Data(repeating: 0x42, count: 2048).write(to: cache.appending(path: "inner/blob.bin"))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmp)
    }

    // MARK: - CleanupEngine

    func testCleanableFolderPassesWithoutReportOnlyContent() async throws {
        let result = try await engine().deepClean(
            findings: [finding(cache, risk: .review)], profileName: "test", dryRun: true, confirmed: true
        )

        XCTAssertEqual(result.succeeded.map(\.originalPath), [cache.path], "\(result.skipped.map(\.reason))")
    }

    func testFolderHoldingAnAdvancedFindingIsSkippedByEveryCleanEntryPoint() async throws {
        let findings = [finding(cache, risk: .safe), finding(cache.appending(path: "inner"), risk: .advanced)]
        let engine = engine()

        let quick = try await engine.quickClean(findings: findings, profileName: "test", dryRun: true)
        let deep = try await engine.deepClean(findings: findings, profileName: "test", dryRun: true, confirmed: true)
        let selected = try await engine.clean(findings: findings, profileName: "test", dryRun: true)
        let results = [("quick", quick), ("deep", deep), ("selected", selected)]

        for (name, result) in results {
            XCTAssertTrue(result.succeeded.isEmpty, "\(name): \(result.succeeded.map(\.originalPath))")
            let folder = result.skipped.first { $0.path == cache.path }
            guard case .holdsProtectedContent = folder?.error else {
                XCTFail("\(name): expected .holdsProtectedContent, got \(String(describing: folder?.error))")
                continue
            }
        }
    }

    func testFolderHoldingACustomGoCacheIsSkipped() async throws {
        let goCache = cache.appending(path: "inner")
        let engine = engine(goCacheLocations: GoCacheLocations(query: { [path = goCache.path] in path }))

        let result = try await engine.clean(findings: [finding(cache, risk: .safe)], profileName: "test", dryRun: true)

        XCTAssertTrue(result.succeeded.isEmpty)
        guard case .holdsProtectedContent = result.skipped.first?.error else {
            return XCTFail("expected .holdsProtectedContent, got \(String(describing: result.skipped.first?.error))")
        }
    }

    // MARK: - ScanPolicy.holdsNeverCleanLocation

    func testHoldsNeverCleanLocationTable() {
        let home = URL(fileURLWithPath: "/Users/u")
        let cases: [(path: String, holds: Bool)] = [
            ("/Users/u/Library/Caches", true),
            ("/Users/u/library/caches", true),
            ("/Users/u/go", true),
            ("/Users/u/go/pkg/mod", true),
            ("/Users/u/.local/share", true),
            ("/Users/u/.local/share/opencode", true),
            ("/Users/u/Library/Containers/com.docker.docker", true),
            ("/Users/u/Library/Caches/com.example.app", false),
            ("/Users/u/.local/share/opencode/log", false),
            ("/Users/u/Projects/go", false),
            ("/Users/other/Library/Caches", false),
        ]
        for testCase in cases {
            XCTAssertEqual(
                ScanPolicy.holdsNeverCleanLocation(URL(fileURLWithPath: testCase.path), home: home, customRoots: []),
                testCase.holds,
                testCase.path
            )
        }
    }

    // MARK: - Helpers

    private func engine(goCacheLocations: GoCacheLocations = GoCacheLocations(query: { nil })) -> CleanupEngine {
        CleanupEngineFixture.make(
            store: CleanupTransactionStore(directory: tmp.appending(path: "store")),
            projectRootsProvider: { [] },
            now: { Date().addingTimeInterval(30 * 86400) },
            goCacheLocations: goCacheLocations
        )
    }

    private func finding(_ url: URL, risk: RiskLevel) -> ScanFinding {
        ScanFinding(
            category: .userCaches, riskLevel: risk, reason: "test", path: url.path,
            sizeBytes: 2048, lastUsed: nil, confidence: 1.0
        )
    }
}
