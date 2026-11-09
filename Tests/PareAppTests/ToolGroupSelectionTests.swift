import XCTest
import PareCore
@testable import PareApp

/// The tool-group checkbox must behave like the category checkbox: safe rows only.
@MainActor
final class ToolGroupSelectionTests: XCTestCase {

    private let safePath = "/Users/u/.npm/_cacache/index-v5/aa"
    private let reviewPath = "/Users/u/.npm/_npx/abc/node_modules/x"

    func testGroupCheckboxTicksSafeRowsAndLeavesReviewRowsAlone() throws {
        let (vm, group) = try loadedGroup(findings: [safeFinding(), reviewFinding()])
        let reviewId = try XCTUnwrap(group.folderIds.subtracting(group.safeFolderIds).first)
        vm.clearSelection()

        vm.toggleToolGroup(group)

        XCTAssertEqual(vm.toolGroupSelectionState(group), .all)
        XCTAssertFalse(vm.isSelected(path: reviewPath))
        XCTAssertTrue(vm.isSelected(path: safePath))
        XCTAssertEqual(vm.selectedReviewCount, 0)
        XCTAssertFalse(group.safeFolderIds.contains(reviewId))

        vm.toggleToolGroup(group)

        XCTAssertEqual(vm.toolGroupSelectionState(group), .none)
        XCTAssertFalse(vm.isSelected(path: safePath))
    }

    func testReviewTickedByHandDoesNotChangeGroupState() throws {
        let (vm, group) = try loadedGroup(findings: [safeFinding(), reviewFinding()])
        vm.clearSelection()
        vm.toggleSelectionOfFolder(containing: reviewPath)

        XCTAssertEqual(vm.toolGroupSelectionState(group), .none)

        vm.toggleToolGroup(group)
        XCTAssertEqual(vm.toolGroupSelectionState(group), .all)

        // Unticking the group leaves the hand-ticked review row selected.
        vm.toggleToolGroup(group)
        XCTAssertEqual(vm.toolGroupSelectionState(group), .none)
        XCTAssertTrue(vm.isSelected(path: reviewPath))
    }

    func testPartialStateWhenOnlySomeSafeRowsAreTicked() throws {
        let second = "/Users/u/.npm/_logs/x.log"
        let (vm, group) = try loadedGroup(findings: [safeFinding(), safeFinding(path: second), reviewFinding()])
        vm.clearSelection()
        let one = try XCTUnwrap(vm.categoryFolderRows[.developerPackageCaches]?.first { group.safeFolderIds.contains($0.id) })

        vm.toggleFolder(one)

        XCTAssertEqual(group.safeFolderIds.count, 2)
        XCTAssertEqual(vm.toolGroupSelectionState(group), .partial)
    }

    func testReviewOnlyGroupIsNotSelectableAndToggleDoesNothing() throws {
        let (vm, group) = try loadedGroup(findings: [reviewFinding()])
        vm.clearSelection()

        XCTAssertFalse(group.isSelectable)
        vm.toggleToolGroup(group)

        XCTAssertEqual(vm.toolGroupSelectionState(group), .none)
        XCTAssertEqual(vm.selectedCandidatesCount, 0)
    }

    // MARK: - Helpers

    private func loadedGroup(findings: [ScanFinding]) throws -> (ScanDashboardViewModel, CategoryToolGroup) {
        let vm = ScanDashboardViewModel()
        vm.applySnapshotResults(ScanReport(findings: findings, summaries: []))
        let group = try XCTUnwrap(vm.categoryToolGroups[.developerPackageCaches]?.first)
        return (vm, group)
    }

    private func safeFinding(path: String? = nil) -> ScanFinding {
        finding(path ?? safePath, risk: .safe)
    }

    private func reviewFinding() -> ScanFinding {
        finding(reviewPath, risk: .review)
    }

    private func finding(_ path: String, risk: RiskLevel) -> ScanFinding {
        ScanFinding(
            category: .developerPackageCaches, riskLevel: risk, reason: "test", path: path,
            sizeBytes: 4096, lastUsed: nil, confidence: 1
        )
    }
}

private extension ScanDashboardViewModel {
    /// Ticks the folder row whose folder covers `path`, as a click on that row would.
    func toggleSelectionOfFolder(containing path: String) {
        let row = categoryFolderRows.values.flatMap { $0 }.first { path.hasPrefix($0.folderPath + "/") }
        if let row { toggleFolder(row) }
    }
}
