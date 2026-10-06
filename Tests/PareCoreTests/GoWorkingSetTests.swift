import XCTest
@testable import PareCore

/// Go's build and module caches are a working set Go manages itself: reported for size, never cleanable.
final class GoWorkingSetTests: XCTestCase {

    private var tmp: URL!

    override func setUpWithError() throws {
        tmp = FileManager.default.temporaryDirectory.appending(path: "pare_test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmp)
    }

    // MARK: - ScanPolicy.isNeverCleanPath

    func testNeverCleanPathTable() {
        let cases: [(path: String, neverClean: Bool)] = [
            ("/Users/u/Library/Caches/go-build", true),
            ("/Users/u/Library/Caches/go-build/ab", true),
            ("/Users/u/Library/Caches/go-build/ab/abcdef-d", true),
            ("/Users/u/go/pkg/mod", true),
            ("/Users/u/go/pkg/mod/cache/download/x", true),
            ("/Users/u/go/pkg/mod/golang.org/toolchain@v0.0.1-go1.22.0.darwin-arm64", true),
            ("/Users/u/go/pkg/mod/github.com/acme/lib@v1.2.3/build", true),
            ("/private/var/folders/xy/T/home/Library/Caches/go-build/01", true),
            ("/Users/u/gopath/pkg/modx", false),
            ("/Users/u/Library/Caches/go-builder", false),
            ("/Users/u/Library/Caches/com.example.app", false),
            ("/Users/u/go/pkg", false),
            ("/Users/u/Projects/go-build", false),
            ("/Users/u/Projects/mod/pkg/go", false),
        ]
        for testCase in cases {
            XCTAssertEqual(
                ScanPolicy.isNeverCleanPath(URL(fileURLWithPath: testCase.path), customRoots: []),
                testCase.neverClean,
                testCase.path
            )
        }
    }

    func testCustomGoEnvLocationIsNeverClean() {
        let custom = [URL(fileURLWithPath: "/Volumes/Fast/gocache"), URL(fileURLWithPath: "/opt/gomodcache")]

        XCTAssertTrue(ScanPolicy.isNeverCleanPath(URL(fileURLWithPath: "/Volumes/Fast/gocache/ab"), customRoots: custom))
        XCTAssertTrue(ScanPolicy.isNeverCleanPath(URL(fileURLWithPath: "/opt/gomodcache"), customRoots: custom))
        XCTAssertFalse(ScanPolicy.isNeverCleanPath(URL(fileURLWithPath: "/Volumes/Fast/gocache-old"), customRoots: custom))
    }

    func testNeverCleanBeatsEveryAllowMarker() {
        let goBuild = URL(fileURLWithPath: "/Users/u/Library/Caches/go-build/ab")
        let modDownload = URL(fileURLWithPath: "/Users/u/go/pkg/mod/cache/download/x")

        XCTAssertFalse(ScanPolicy.isLowImpactPath(goBuild))
        XCTAssertFalse(ScanPolicy.matchesPersonaPath(modDownload, allowedMarkers: ["/go/pkg/mod/cache", "/go/"]))
        XCTAssertFalse(ScanPolicy.isReconstructibleCachePath(goBuild))
        XCTAssertFalse(ScanPolicy.isReconstructibleCachePath(modDownload))
        XCTAssertTrue(ScanPolicy.isLowImpactPath(URL(fileURLWithPath: "/Users/u/Library/Caches/com.example.app")),
                      "control: ordinary caches stay low-impact")
    }

    // MARK: - go env resolution

    func testGoEnvOutputParsing() {
        let both = GoCacheLocations.parse("/Volumes/Fast/gocache\n/opt/gomodcache/\n")
        XCTAssertEqual(both.build?.path, "/Volumes/Fast/gocache")
        XCTAssertEqual(both.module?.path, "/opt/gomodcache")

        let cacheOff = GoCacheLocations.parse("off\n/opt/gomodcache\n")
        XCTAssertNil(cacheOff.build)
        XCTAssertEqual(cacheOff.module?.path, "/opt/gomodcache")

        XCTAssertEqual(GoCacheLocations.parse("/\nrelative/dir\n"), .empty)
        XCTAssertEqual(GoCacheLocations.parse(nil), .empty)
    }

    func testLocationsResolveOnceAndAbsentGoYieldsNoRoots() async {
        let queries = LockedQueryCount()
        let locations = GoCacheLocations(query: {
            queries.increment()
            return nil
        })

        let first = await locations.resolveIfNeeded()
        let second = await locations.resolveIfNeeded()

        XCTAssertEqual(first, .empty)
        XCTAssertEqual(second, .empty)
        XCTAssertEqual(queries.value, 1)
        XCTAssertEqual(locations.resolvedRoots, [])
    }

    // MARK: - GoCachesRule

    func testGoBuildIsReportOnlyWorkingSet() async throws {
        let goBuild = try makeCache("Library/Caches/go-build")
        let modCache = try makeCache("go/pkg/mod/cache/download")
        let rule = GoCachesRule(locations: GoCacheLocations(query: { nil }))

        let findings = await rule.customScan(environment: ScanEnvironment(homeDirectory: tmp)) ?? []

        let build = try XCTUnwrap(findings.first { $0.path == goBuild.path })
        XCTAssertEqual(build.riskLevel, .advanced)
        XCTAssertEqual(build.annotations, [.workingSet(selfTrimDays: 5)])
        XCTAssertTrue(build.reason.contains("unused for 5 days"), build.reason)

        let modulePath = modCache.deletingLastPathComponent().deletingLastPathComponent().path
        let module = try XCTUnwrap(findings.first { $0.path == modulePath }, "\(findings.map(\.path))")
        XCTAssertEqual(module.riskLevel, .advanced)
        XCTAssertEqual(module.annotations, [.workingSet(selfTrimDays: nil)])
        XCTAssertEqual(findings.count, 2)
    }

    func testCustomGoEnvLocationsAreReported() async throws {
        let custom = try makeCache("elsewhere/gocache")
        let rule = GoCachesRule(locations: GoCacheLocations(query: { [path = custom.path] in path + "\n" }))

        let findings = await rule.customScan(environment: ScanEnvironment(homeDirectory: tmp)) ?? []

        XCTAssertEqual(findings.map(\.path), [custom.path])
        XCTAssertEqual(findings.first?.riskLevel, .advanced)
    }

    func testGoFindingsExcludedFromReclaimableTotal() async throws {
        _ = try makeCache("Library/Caches/go-build")
        _ = try makeCache("go/pkg/mod/cache/download")
        let runner = ScanRunner(environment: ScanEnvironment(homeDirectory: tmp))

        let report = await runner.run(rules: [GoCachesRule(locations: GoCacheLocations(query: { nil }))])

        XCTAssertEqual(report.findings.count, 2)
        XCTAssertEqual(report.totalReclaimableBytes, 0)
    }

    // MARK: - CleanupEngine

    func testCleanupSkipsGoPathMislabelledSafe() async throws {
        let goBuild = try makeCache("Library/Caches/go-build")
        let moduleBuild = try makeCache("go/pkg/mod/github.com/acme/lib@v1.2.3/build")
        try Data("module acme/lib\n".utf8).write(to: moduleBuild.deletingLastPathComponent().appending(path: "go.mod"))
        let engine = CleanupEngine(
            store: CleanupTransactionStore(directory: tmp.appending(path: "store")),
            projectRootsProvider: { [] },
            goCacheLocations: GoCacheLocations(query: { nil })
        )
        let findings = [
            finding(goBuild, category: .developerPackageCaches),
            finding(moduleBuild, category: .projectArtifacts),
        ]

        let result = try await engine.clean(findings: findings, profileName: "test", dryRun: true)

        XCTAssertTrue(result.succeeded.isEmpty, "\(result.succeeded.map(\.originalPath))")
        XCTAssertEqual(result.skipped.count, 2)
        for item in result.skipped {
            guard case .workingSetProtected = item.error else {
                XCTFail("expected .workingSetProtected for \(item.path), got \(item.error)")
                continue
            }
        }
    }

    func testCleanupSkipsCustomGoEnvLocation() async throws {
        let custom = try makeCache("Library/Caches/custom-gocache")
        let engine = CleanupEngine(
            store: CleanupTransactionStore(directory: tmp.appending(path: "store")),
            projectRootsProvider: { [] },
            goCacheLocations: GoCacheLocations(query: { [path = custom.path] in path })
        )

        let result = try await engine.clean(
            findings: [finding(custom, category: .userCaches)], profileName: "test", dryRun: true
        )

        XCTAssertTrue(result.succeeded.isEmpty)
        guard case .some(.workingSetProtected(_)) = result.skipped.first?.error else {
            return XCTFail("expected .workingSetProtected, got \(result.skipped)")
        }
    }

    // MARK: - Helpers

    private func makeCache(_ relative: String) throws -> URL {
        let dir = tmp.appending(path: relative)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appending(path: "entry.bin")
        try Data(repeating: 0x42, count: 2048).write(to: file)
        let old = Date().addingTimeInterval(-30 * 24 * 60 * 60)
        try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: file.path)
        try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: dir.path)
        return URL(fileURLWithPath: dir.path)
    }

    private func finding(_ url: URL, category: ScanCategory) -> ScanFinding {
        ScanFinding(
            category: category,
            riskLevel: .safe,
            reason: "mislabelled",
            path: url.path,
            sizeBytes: 2048,
            lastUsed: Date().addingTimeInterval(-30 * 24 * 60 * 60),
            confidence: 1.0
        )
    }
}

private final class LockedQueryCount: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int { lock.withLock { count } }

    func increment() { lock.withLock { count += 1 } }
}
