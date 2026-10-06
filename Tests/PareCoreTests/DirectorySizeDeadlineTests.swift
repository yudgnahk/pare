import XCTest
@testable import PareCore

/// Folder sizing stops at a deadline and reports "at least X" instead of a guess or zero.
final class DirectorySizeDeadlineTests: XCTestCase {

    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "pare_size_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for index in 0..<10 {
            try Data(repeating: 0x42, count: 8192).write(to: root.appending(path: "file\(index).bin"))
        }
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    // MARK: - FileSystemUtils

    func testNoDeadlineWalksEverything() {
        let result = FileSystemUtils.directorySize(at: root, deadline: nil)

        XCTAssertTrue(result.isComplete)
        XCTAssertEqual(result.bytes, FileSystemUtils.directorySize(url: root))
        XCTAssertGreaterThan(result.bytes, 0)
    }

    func testDeadlineHitMidWalkKeepsPartialBytes() {
        let clock = SteppingClock(timesBeforeDeadline: 3)
        let full = FileSystemUtils.directorySize(url: root)

        let result = FileSystemUtils.directorySize(at: root, deadline: clock.deadline, now: clock.now, checkEvery: 1)

        XCTAssertFalse(result.isComplete)
        XCTAssertGreaterThan(result.bytes, 0, "an incomplete walk keeps what it counted")
        XCTAssertLessThan(result.bytes, full)
    }

    func testDeadlineAlreadyPassedStopsAtOnce() {
        let past = Date().addingTimeInterval(-1)

        let result = FileSystemUtils.directorySize(at: root, deadline: past)

        XCTAssertFalse(result.isComplete)
        XCTAssertEqual(result.bytes, 0)
    }

    // MARK: - Size index and finding builder

    func testSizeIndexBoundsEachDirectoryAndMemoizes() {
        let bounded = DirectorySizeIndex(budgetSeconds: 0, now: { Date(timeIntervalSinceReferenceDate: 0) })

        let first = bounded.directorySizeResult(url: root)
        let second = bounded.directorySizeResult(url: root)

        XCTAssertFalse(first.isComplete)
        XCTAssertEqual(first, second)
        XCTAssertEqual(bounded.directorySize(url: root), FileSystemUtils.directorySize(url: root),
                       "the unbounded API still returns the full size")
        XCTAssertTrue(DirectorySizeIndex().directorySizeResult(url: root).isComplete)
    }

    func testFindingBuilderPropagatesIncompleteSize() throws {
        let bounded = DirectorySizeIndex(budgetSeconds: 0, now: { Date(timeIntervalSinceReferenceDate: 0) })

        let partial = ScanFindingBuilder.directoryFindings(
            at: root, category: .userCaches, riskLevel: .safe, reason: "test", confidence: 1, sizeIndex: bounded
        )
        let complete = ScanFindingBuilder.directoryFindings(
            at: root, category: .userCaches, riskLevel: .safe, reason: "test", confidence: 1, sizeIndex: DirectorySizeIndex()
        )

        let unknown = try XCTUnwrap(partial.first, "an unfinished size is still reported, never dropped as zero")
        XCTAssertFalse(unknown.isSizeComplete)
        XCTAssertTrue(try XCTUnwrap(complete.first).isSizeComplete)
    }

    // MARK: - Presentation

    func testFindingSizeText() {
        XCTAssertEqual(ScanReportPresenter.formatFindingSize(bytes: 2_000_000, isComplete: true), ScanReportPresenter.formatBytes(2_000_000))
        XCTAssertEqual(ScanReportPresenter.formatFindingSize(bytes: 2_000_000, isComplete: false), "≥ " + ScanReportPresenter.formatBytes(2_000_000))
        XCTAssertEqual(ScanReportPresenter.formatFindingSize(bytes: 0, isComplete: false), "size unknown")
    }

    func testTotalSaysAtLeastWhenAnyReclaimableFindingIsPartial() {
        let complete = finding(path: "/a", complete: true, risk: .safe)
        let partial = finding(path: "/b", complete: false, risk: .review)
        let partialAdvanced = finding(path: "/c", complete: false, risk: .advanced)

        XCTAssertFalse(report([complete]).hasPartialSizes)
        XCTAssertTrue(report([complete, partial]).hasPartialSizes)
        XCTAssertFalse(report([complete, partialAdvanced]).hasPartialSizes, "report-only findings are not in the total")

        XCTAssertEqual(ScanReportPresenter.formatTotal(bytes: 5_000_000, isPartial: false), ScanReportPresenter.formatBytes(5_000_000))
        XCTAssertEqual(ScanReportPresenter.formatTotal(bytes: 5_000_000, isPartial: true), "at least " + ScanReportPresenter.formatBytes(5_000_000))
    }

    // MARK: - Helpers

    private func finding(path: String, complete: Bool, risk: RiskLevel) -> ScanFinding {
        ScanFinding(
            category: .userCaches, riskLevel: risk, reason: "test", path: path,
            sizeBytes: 1000, lastUsed: nil, confidence: 1, isSizeComplete: complete
        )
    }

    private func report(_ findings: [ScanFinding]) -> ScanReport {
        ScanReport(findings: findings, summaries: [])
    }
}

/// Reads as the start time for the first `timesBeforeDeadline` calls, then as well past the deadline.
private final class SteppingClock: @unchecked Sendable {
    private let lock = NSLock()
    private var calls = 0
    private let timesBeforeDeadline: Int
    private let start = Date(timeIntervalSinceReferenceDate: 0)

    init(timesBeforeDeadline: Int) {
        self.timesBeforeDeadline = timesBeforeDeadline
    }

    var deadline: Date { start.addingTimeInterval(10) }

    var now: @Sendable () -> Date {
        { [self] in
            lock.withLock {
                calls += 1
                return calls <= timesBeforeDeadline ? start : start.addingTimeInterval(60)
            }
        }
    }
}
