import XCTest
@testable import PareCore

/// Growth tracking: a snapshot per scan, pruned to the last N, and what grew since the previous one.
final class GrowthSnapshotTests: XCTestCase {

    private static let megabyte: Int64 = 1024 * 1024
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appending(path: "pare_growth_\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    // MARK: - Store

    func testRoundTripReturnsTheNewestSnapshot() throws {
        let store = GrowthSnapshotStore(directory: directory)
        let older = snapshot(at: 1_000, categories: ["User Caches": 10], paths: [:])
        let newer = snapshot(at: 2_000, categories: ["User Caches": 20], paths: ["/a": 300 * Self.megabyte])

        try store.save(older)
        try store.save(newer)

        XCTAssertEqual(store.latest(), newer)
    }

    func testPrunesToTheRetainedCount() throws {
        let store = GrowthSnapshotStore(directory: directory, retainedCount: 3)
        for index in 0..<5 {
            try store.save(snapshot(at: TimeInterval(1_000 + index), categories: [:], paths: [:]))
        }

        XCTAssertEqual(store.snapshotFiles().count, 3)
        XCTAssertEqual(store.latest()?.takenAt, Date(timeIntervalSince1970: 1_004))
    }

    func testCorruptNewestFileIsSkipped() throws {
        let store = GrowthSnapshotStore(directory: directory)
        let good = snapshot(at: 1_000, categories: ["Logs": 5], paths: [:])
        try store.save(good)
        try Data("{ not json".utf8).write(to: directory.appending(path: "growth-9999999999999.json"))

        XCTAssertEqual(store.latest(), good)
    }

    // MARK: - Delta

    func testDeltaTable() {
        let previous = snapshot(at: 1_000, categories: [:], paths: [
            "/grew": 500 * Self.megabyte,
            "/shrank": 900 * Self.megabyte,
            "/noise": 500 * Self.megabyte,
            "/vanished": 800 * Self.megabyte,
        ])
        let current = snapshot(at: 2_000, categories: [:], paths: [
            "/grew": 3_000 * Self.megabyte,
            "/shrank": 100 * Self.megabyte,
            "/noise": 510 * Self.megabyte,
            "/new": 200 * Self.megabyte,
        ])

        let delta = GrowthDelta.compute(previous: previous, current: current)

        XCTAssertEqual(delta.paths.map(\.key), ["/grew", "/new"], "sorted by growth; shrink, noise and vanished ignored")
        XCTAssertEqual(delta.paths.first?.grewBy, 2_500 * Self.megabyte)
        XCTAssertEqual(delta.paths.last?.grewBy, 200 * Self.megabyte, "a new path grew from zero")
        XCTAssertEqual(delta.paths.map(\.isNew), [false, true])
    }

    func testPathCrossingTheReportingFloorCountsOnlyItsChange() {
        let previous = snapshot(at: 1, categories: [:], paths: ["/crossing": 90 * Self.megabyte, "/jump": 40 * Self.megabyte])
        let current = snapshot(at: 2, categories: [:], paths: [
            "/crossing": 110 * Self.megabyte, "/jump": 400 * Self.megabyte, "/small": 80 * Self.megabyte,
        ])

        let delta = GrowthDelta.compute(previous: previous, current: current)

        XCTAssertEqual(delta.paths.map(\.key), ["/jump"], "20 MB is noise; a path under the reporting floor is not reported")
        XCTAssertEqual(delta.paths.first?.grewBy, 360 * Self.megabyte)
    }

    func testIncompleteBaselineYieldsNoGrowth() {
        let partial = GrowthSnapshot(takenAt: Date(timeIntervalSince1970: 1), perCategory: [:], perPath: [:], isComplete: false)
        let current = snapshot(at: 2, categories: ["Logs": 900 * Self.megabyte], paths: ["/a": 900 * Self.megabyte])

        XCTAssertTrue(GrowthDelta.compute(previous: partial, current: current).isEmpty)
    }

    func testLatestCompleteSkipsPartialSnapshots() throws {
        let store = GrowthSnapshotStore(directory: directory)
        let full = snapshot(at: 1_000, categories: ["Logs": 5], paths: [:])
        let partial = GrowthSnapshot(takenAt: Date(timeIntervalSince1970: 2_000), perCategory: [:], perPath: [:], isComplete: false)
        try store.save(full)
        try store.save(partial)

        XCTAssertEqual(store.latest(), partial)
        XCTAssertEqual(store.latestComplete(), full)
    }

    func testSnapshotWithoutCompletenessFlagIsNotABaseline() throws {
        let store = GrowthSnapshotStore(directory: directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let legacy = #"{"takenAt":1000,"perCategory":{},"perPath":{}}"#
        try Data(legacy.utf8).write(to: directory.appending(path: "growth-0000000001000.json"))

        XCTAssertNotNil(store.latest())
        XCTAssertNil(store.latestComplete())
    }

    func testReportWithFailuresOrUnreadableLocationsMakesAPartialSnapshot() {
        let summaries = [ScanCategorySummary(category: .userCaches, reclaimableBytes: 1, fileCount: 1)]
        let failure = ScanRuleFailure(ruleID: "r", ruleTitle: "R", message: "boom")
        let incomplete = ScanIncompleteRule(ruleID: "r", ruleTitle: "R", message: "stopped at the deadline")
        let partialSize = ScanFinding(
            category: .userCaches, riskLevel: .safe, reason: "test", path: "/Users/u/Library/Caches/a",
            sizeBytes: 1, lastUsed: nil, confidence: 1, isSizeComplete: false
        )
        let cases: [(name: String, report: ScanReport, complete: Bool)] = [
            ("clean", ScanReport(findings: [], summaries: summaries), true),
            ("rule failed", ScanReport(findings: [], summaries: summaries, ruleFailures: [failure]), false),
            ("unreadable", ScanReport(findings: [], summaries: summaries, unreadableLocations: ["/x"]), false),
            ("rule stopped early", ScanReport(findings: [], summaries: summaries, incompleteRules: [incomplete]), false),
            ("size cut short", ScanReport(findings: [partialSize], summaries: summaries), false),
        ]
        for testCase in cases {
            XCTAssertEqual(GrowthSnapshot(report: testCase.report).isComplete, testCase.complete, testCase.name)
        }
    }

    func testAdvancedFindingsStayOutOfPerPath() {
        let safe = finding("/Users/u/Library/Caches/a", bytes: 200 * Self.megabyte)
        let advanced = ScanFinding(
            category: .userCaches, riskLevel: .advanced, reason: "test", path: "/Users/u/Library/b",
            sizeBytes: 500 * Self.megabyte, lastUsed: nil, confidence: 1
        )
        let report = ScanReport(findings: [safe, advanced], summaries: [])

        XCTAssertEqual(Set(GrowthSnapshot(report: report).perPath.keys), [GrowthSnapshot.key(safe.path)])
    }

    func testExplainOnlyAndWorkingSetFindingsStayOutOfPerPath() {
        let safe = finding("/Users/u/Library/Caches/a", bytes: 200 * Self.megabyte)
        let explainOnly = ScanFinding(
            category: .diagnostics, riskLevel: .review, reason: "test", path: "/private/var/vm",
            sizeBytes: 500 * Self.megabyte, lastUsed: nil, confidence: 1, annotations: [.explainOnly(action: "restart")]
        )
        let workingSet = ScanFinding(
            category: .userCaches, riskLevel: .safe, reason: "test", path: "/Users/u/Library/Caches/go-build",
            sizeBytes: 500 * Self.megabyte, lastUsed: nil, confidence: 1, annotations: [.workingSet(selfTrimDays: 5)]
        )
        let report = ScanReport(findings: [safe, explainOnly, workingSet], summaries: [])

        XCTAssertEqual(Set(GrowthSnapshot(report: report).perPath.keys), [GrowthSnapshot.key(safe.path)])
    }

    func testPathsAreRecordedFromTheTrackedFloor() {
        let report = ScanReport(findings: [
            finding("/Users/u/a", bytes: 20 * Self.megabyte), finding("/Users/u/b", bytes: 5 * Self.megabyte),
        ], summaries: [])

        XCTAssertEqual(Set(GrowthSnapshot(report: report).perPath.keys), [GrowthSnapshot.key("/Users/u/a")])
    }

    func testCategoryDeltasUseTheSameRules() {
        let previous = snapshot(at: 1, categories: ["Developer Build Artifacts": 1_000 * Self.megabyte, "Logs": 100], paths: [:])
        let current = snapshot(at: 2, categories: ["Developer Build Artifacts": 4_100 * Self.megabyte, "Logs": 200], paths: [:])

        let delta = GrowthDelta.compute(previous: previous, current: current)

        XCTAssertEqual(delta.categories.map(\.key), ["Developer Build Artifacts"])
        XCTAssertTrue(GrowthDelta.compute(previous: current, current: current).isEmpty)
    }

    func testSnapshotFromReportUsesCanonicalKeysAndTrackedSize() {
        let big = finding("/var/folders/ab/T/Cache", bytes: 200 * Self.megabyte)
        let alias = finding("/private/var/folders/AB/T/cache", bytes: 100 * Self.megabyte)
        let small = finding("/Users/u/Library/Caches/tiny", bytes: 1024)
        let report = ScanReport(
            findings: [big, alias, small],
            summaries: [ScanCategorySummary(category: .userCaches, reclaimableBytes: 42, fileCount: 3)]
        )

        let snapshot = GrowthSnapshot(report: report, takenAt: Date(timeIntervalSince1970: 0))

        XCTAssertEqual(snapshot.perPath, ["/private/var/folders/ab/t/cache": 300 * Self.megabyte])
        XCTAssertEqual(snapshot.perCategory, ["User Caches": 42])
    }

    // MARK: - Helpers

    private func snapshot(at seconds: TimeInterval, categories: [String: Int64], paths: [String: Int64]) -> GrowthSnapshot {
        GrowthSnapshot(takenAt: Date(timeIntervalSince1970: seconds), perCategory: categories, perPath: paths)
    }

    private func finding(_ path: String, bytes: Int64) -> ScanFinding {
        ScanFinding(category: .userCaches, riskLevel: .safe, reason: "test", path: path, sizeBytes: bytes, lastUsed: nil, confidence: 1)
    }
}
