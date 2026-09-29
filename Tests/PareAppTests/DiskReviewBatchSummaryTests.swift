import XCTest
import PareCore
@testable import PareApp

final class DiskReviewBatchSummaryTests: XCTestCase {

    private let parentPath = "/Users/k/.npm/_cacache"

    private func makeFinding(path: String, sizeBytes: Int64, riskLevel: RiskLevel = .safe) -> ScanFinding {
        ScanFinding(
            category: .userCaches,
            riskLevel: riskLevel,
            reason: "test fixture",
            path: path,
            sizeBytes: sizeBytes,
            lastUsed: nil,
            confidence: 1.0
        )
    }

    private func formatBytes(_ bytes: Int64) -> String { "\(bytes) B" }

    /// Three small files inside one finding stage the whole finding, and the label must say so.
    func testInsideFindingRowsCollapseToOneWholeFinding() {
        let parent = makeFinding(path: parentPath, sizeBytes: 2_300)
        let summary = DiskReviewBatchSummary(resolutions: Array(repeating: DiskReviewResolution.insideFinding(parent), count: 3))

        XCTAssertEqual(summary.selectedItemCount, 3)
        XCTAssertEqual(summary.findingPaths, [parentPath])
        XCTAssertEqual(summary.totalBytes, 2_300)
        XCTAssertEqual(summary.addLabel(formatBytes: formatBytes), "Add 1 finding (2300 B) covering 3 selected items")
        XCTAssertNil(summary.reviewRiskWarning)
    }

    func testCoveredRowsCountEveryDistinctFindingAndFlagReviewRisk() {
        let safe = makeFinding(path: "/Users/k/Library/Caches/a", sizeBytes: 100)
        let review = makeFinding(path: "/Users/k/Library/Caches/b", sizeBytes: 200, riskLevel: .review)
        let summary = DiskReviewBatchSummary(resolutions: [.covered([safe, review]), .covered([safe])])

        XCTAssertEqual(summary.selectedItemCount, 2)
        XCTAssertEqual(summary.findingCount, 2)
        XCTAssertEqual(summary.totalBytes, 300)
        XCTAssertEqual(summary.reviewRiskCount, 1)
        XCTAssertEqual(summary.addLabel(formatBytes: formatBytes), "Add 2 findings (300 B) covering 2 selected items")
        XCTAssertEqual(summary.reviewRiskWarning, "Includes 1 Review-risk finding")
    }

    /// A finding nested inside another staged finding is not double-counted, matching the tray.
    func testNestedFindingIsDroppedInFavourOfItsParent() {
        let parent = makeFinding(path: parentPath, sizeBytes: 1_000)
        let child = makeFinding(path: parentPath + "/index-v5", sizeBytes: 400, riskLevel: .review)
        let summary = DiskReviewBatchSummary(resolutions: [.covered([child]), .insideFinding(parent)])

        XCTAssertEqual(summary.findingPaths, [parentPath])
        XCTAssertEqual(summary.totalBytes, 1_000)
        XCTAssertEqual(summary.reviewRiskCount, 0)
    }

    func testUnaddableRowsAreNotCounted() {
        let finding = makeFinding(path: parentPath, sizeBytes: 10)
        let summary = DiskReviewBatchSummary(resolutions: [.notCandidate, .noScan, .insideFinding(finding)])

        XCTAssertEqual(summary.selectedItemCount, 1)
        XCTAssertEqual(summary.addLabel(formatBytes: formatBytes), "Add 1 finding (10 B) covering 1 selected item")
    }

    func testPrivateAliasSpellingsCountOnce() {
        let summary = DiskReviewBatchSummary(resolutions: [
            .covered([makeFinding(path: "/var/folders/ab/T/cache", sizeBytes: 50)]),
            .covered([makeFinding(path: "/private/var/folders/ab/T/cache", sizeBytes: 50)])
        ])

        XCTAssertEqual(summary.findingCount, 1)
        XCTAssertEqual(summary.totalBytes, 50)
    }
}
