import XCTest
@testable import PareCore

final class ScanReportPresenterTests: XCTestCase {

    private func finding(
        _ path: String,
        risk: RiskLevel,
        bytes: Int64,
        category: ScanCategory = .userCaches
    ) -> ScanFinding {
        ScanFinding(
            category: category,
            riskLevel: risk,
            reason: "test",
            path: path,
            sizeBytes: bytes,
            lastUsed: nil,
            confidence: 0.9
        )
    }

    // MARK: - largestItems

    func testLargestItemsExcludesAdvancedAndOrdersSafeThenReview() {
        let findings = [
            finding("/a", risk: .review, bytes: 500),
            finding("/b", risk: .safe, bytes: 300),
            finding("/c", risk: .advanced, bytes: 900),
            finding("/d", risk: .safe, bytes: 100),
        ]
        let items = ScanReportPresenter.largestItems(from: findings, limit: 10)
        XCTAssertEqual(items.map(\.path), ["/b", "/d", "/a"])
    }

    func testLargestItemsAppliesLimitBeforeRiskGrouping() {
        let findings = [
            finding("/big-review", risk: .review, bytes: 1000),
            finding("/small-safe", risk: .safe, bytes: 10),
        ]
        let items = ScanReportPresenter.largestItems(from: findings, limit: 1)
        XCTAssertEqual(items.map(\.path), ["/big-review"])
    }

    // MARK: - largeFileGroups

    func testLargeFileGroupsFiltersBelowThresholdAndSortsGroups() {
        let big = ScanPolicy.largeFileThresholdBytes + 1
        let findings = [
            finding("/logs/one", risk: .safe, bytes: big, category: .logsAndCrashReports),
            finding("/caches/one", risk: .review, bytes: big * 3, category: .userCaches),
            finding("/caches/two", risk: .safe, bytes: big * 2, category: .userCaches),
            finding("/tiny", risk: .safe, bytes: 1, category: .userCaches),
        ]
        let groups = ScanReportPresenter.largeFileGroups(from: findings)
        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups[0].category, .userCaches)
        XCTAssertEqual(groups[0].totalBytes, big * 5)
        // SAFE before REVIEW inside a group even when REVIEW is larger.
        XCTAssertEqual(groups[0].files.map(\.path), ["/caches/two", "/caches/one"])
        XCTAssertEqual(groups[1].category, .logsAndCrashReports)
    }

    // MARK: - formatBytes / riskTag

    func testFormatBytesUsesTerabytes() {
        let twoTB: Int64 = 2_000_000_000_000
        XCTAssertTrue(ScanReportPresenter.formatBytes(twoTB).contains("TB"))
    }

    func testRiskTags() {
        XCTAssertEqual(ScanReportPresenter.riskTag(.safe), "[SAFE]")
        XCTAssertEqual(ScanReportPresenter.riskTag(.review), "[REVIEW]")
        XCTAssertEqual(ScanReportPresenter.riskTag(.advanced), "[ADVANCED]")
    }
}
