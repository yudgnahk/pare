import XCTest
@testable import PareCore

/// A cache that grows straight back after cleaning is a working set: demoted to review, never auto-cleaned.
final class RegrowthDetectorTests: XCTestCase {

    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private let gb: Int64 = 1_000_000_000
    private let day: TimeInterval = 24 * 60 * 60
    private let path = "/Users/u/Library/Caches/go-build"

    func testRegrowthDecisions() {
        let cases: [(name: String, history: [CleanupTransaction], finding: ScanFinding, demoted: Bool)] = [
            ("regrew past ratio", [trashed(path, daysAgo: 3, bytes: 6_930_000_000)], finding(path, bytes: 1_300_000_000), true),
            ("cleaned outside window", [trashed(path, daysAgo: 20, bytes: 6 * gb)], finding(path, bytes: 5 * gb), false),
            ("tiny regrowth", [trashed(path, daysAgo: 3, bytes: 7 * gb)], finding(path, bytes: 10_000_000), false),
            ("cleaned twice in window",
             [trashed(path, daysAgo: 10, bytes: 5 * gb), trashed(path, daysAgo: 2, bytes: 4 * gb)],
             finding(path, bytes: 1_000_000), true),
            ("never cleaned", [trashed("/Users/u/Library/Caches/other", daysAgo: 1, bytes: gb)], finding(path, bytes: gb), false),
            ("dry run ignored", [trashed(path, daysAgo: 1, bytes: gb, dryRun: true)], finding(path, bytes: gb), false),
            ("alias and case spelling",
             [trashed("/var/folders/ab/T/Tool/Cache", daysAgo: 1, bytes: gb)],
             finding("/private/var/folders/ab/T/tool/cache", bytes: gb), true),
        ]
        for testCase in cases {
            let result = detector(testCase.history).apply(to: [testCase.finding])
            XCTAssertEqual(result.count, 1, testCase.name)
            XCTAssertEqual(result.first?.riskLevel, testCase.demoted ? .review : .safe, testCase.name)
            XCTAssertEqual(result.first?.reason.contains("likely an active working set"), testCase.demoted, testCase.name)
        }
    }

    func testDemotedReasonNamesSizeAndDays() throws {
        let result = detector([trashed(path, daysAgo: 3, bytes: 6_930_000_000)])
            .apply(to: [finding(path, bytes: 1_300_000_000)])

        let reason = try XCTUnwrap(result.first?.reason)
        XCTAssertEqual(reason, "Go cache — came back to \(format(1_300_000_000)) within 3 days of the last clean; "
            + "likely an active working set")
    }

    func testRegrowthWithinHoursSaysOneDay() throws {
        let history = [trashed(path, daysAgo: 0.125, bytes: 6_930_000_000)]

        let reason = try XCTUnwrap(detector(history).apply(to: [finding(path, bytes: 1_300_000_000)]).first?.reason)

        XCTAssertTrue(reason.contains("within 1 day of"), reason)
    }

    func testAdvancedFindingsAreUntouched() {
        let advanced = finding(path, bytes: gb, risk: .advanced)

        let result = detector([trashed(path, daysAgo: 1, bytes: gb)]).apply(to: [advanced])

        XCTAssertEqual(result.first?.riskLevel, .advanced)
        XCTAssertEqual(result.first?.reason, advanced.reason)
    }

    func testReviewFindingKeepsReviewAndGainsExplanation() {
        let review = finding(path, bytes: gb, risk: .review)

        let result = detector([trashed(path, daysAgo: 1, bytes: gb)]).apply(to: [review])

        XCTAssertEqual(result.first?.riskLevel, .review)
        XCTAssertTrue(result.first?.reason.contains("likely an active working set") ?? false)
    }

    // MARK: - History from the transaction store

    func testEmptyMissingOrCorruptStoreChangesNothing() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "pare_regrowth_\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let missing = CleanupTransactionStore(directory: root.appending(path: "missing"))
        let corruptDir = root.appending(path: "corrupt")
        try FileManager.default.createDirectory(at: corruptDir, withIntermediateDirectories: true)
        try Data("{ not json".utf8).write(to: corruptDir.appending(path: "\(UUID().uuidString).json"))
        let corrupt = CleanupTransactionStore(directory: corruptDir)

        for store in [missing, corrupt] {
            let original = finding(path, bytes: gb)
            let result = RegrowthDetector(store: store, now: { self.now }).apply(to: [original])
            XCTAssertEqual(result.first?.riskLevel, .safe)
            XCTAssertEqual(result.first?.reason, original.reason)
        }
    }

    func testStoreHistoryIsUsedAlongsideCorruptRecords() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "pare_regrowth_\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = CleanupTransactionStore(directory: root)
        try store.save(trashed(path, daysAgo: 2, bytes: 3 * gb))
        try Data("garbage".utf8).write(to: root.appending(path: "\(UUID().uuidString).json"))

        let result = RegrowthDetector(store: store, now: { self.now }).apply(to: [finding(path, bytes: gb)])

        XCTAssertEqual(result.first?.riskLevel, .review)
    }

    // MARK: - Helpers

    private func detector(_ history: [CleanupTransaction]) -> RegrowthDetector {
        RegrowthDetector(history: { history }, now: { self.now })
    }

    private func trashed(_ path: String, daysAgo: Double, bytes: Int64, dryRun: Bool = false) -> CleanupTransaction {
        CleanupTransaction(
            timestamp: now.addingTimeInterval(-daysAgo * day),
            profileName: "all",
            isDryRun: dryRun,
            items: [CleanupItem(originalPath: path, trashedPath: dryRun ? nil : "/Users/u/.Trash/x",
                                sizeBytes: bytes, reason: "Go cache", riskLevel: .safe)]
        )
    }

    private func finding(_ path: String, bytes: Int64, risk: RiskLevel = .safe) -> ScanFinding {
        ScanFinding(category: .developerPackageCaches, riskLevel: risk, reason: "Go cache", path: path,
                    sizeBytes: bytes, lastUsed: nil, confidence: 1.0)
    }

    private func format(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
