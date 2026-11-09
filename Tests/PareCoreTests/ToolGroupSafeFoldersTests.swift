import XCTest
@testable import PareCore

final class ToolGroupSafeFoldersTests: XCTestCase {

    func testMixedGroupKeepsReviewRowsOutOfSafeFolderIds() throws {
        let rows = [
            row("safe-cache", risk: .safe),
            row("review-site-data", risk: .review),
        ]

        let group = try XCTUnwrap(FolderRollup.makeToolGroups(category: .browserCaches, rows: rows).first)

        XCTAssertEqual(group.folderIds, ["safe-cache", "review-site-data"])
        XCTAssertEqual(group.safeFolderIds, ["safe-cache"])
        XCTAssertTrue(group.isSelectable)
        XCTAssertEqual(group.riskLevel, .review)
    }

    func testReviewOnlyGroupHasNoSafeIdsAndIsNotSelectable() throws {
        let rows = [row("a", risk: .review), row("b", risk: .review)]

        let group = try XCTUnwrap(FolderRollup.makeToolGroups(category: .browserCaches, rows: rows).first)

        XCTAssertTrue(group.safeFolderIds.isEmpty)
        XCTAssertFalse(group.isSelectable)
    }

    func testSafeRowThatIsNotSelectableIsExcluded() throws {
        let rows = [row("empty", risk: .safe, selectable: false), row("ok", risk: .safe)]

        let group = try XCTUnwrap(FolderRollup.makeToolGroups(category: .browserCaches, rows: rows).first)

        XCTAssertEqual(group.safeFolderIds, ["ok"])
    }

    private func row(_ id: String, risk: RiskLevel, selectable: Bool = true) -> CategoryFolderRow {
        CategoryFolderRow(
            id: id, folderPath: "/x/\(id)", displayPath: "~/x/\(id)", totalBytes: 10, itemCount: 1,
            riskLevel: risk, isSelectable: selectable, toolName: "Chrome"
        )
    }
}
