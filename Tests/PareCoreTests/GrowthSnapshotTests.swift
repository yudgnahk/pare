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
    }

    func testCategoryDeltasUseTheSameRules() {
        let previous = snapshot(at: 1, categories: ["Developer Build Artifacts": 1_000 * Self.megabyte, "Logs": 100], paths: [:])
        let current = snapshot(at: 2, categories: ["Developer Build Artifacts": 4_100 * Self.megabyte, "Logs": 200], paths: [:])

        let delta = GrowthDelta.compute(previous: previous, current: current)

        XCTAssertEqual(delta.categories.map(\.key), ["Developer Build Artifacts"])
        XCTAssertTrue(GrowthDelta.compute(previous: current, current: current).isEmpty)
    }

    func testSnapshotFromReportUsesCanonicalKeysAndMinimumSize() {
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
