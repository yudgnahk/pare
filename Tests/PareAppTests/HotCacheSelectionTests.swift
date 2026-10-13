import XCTest
import PareCore
@testable import PareApp

/// Hot cache rows start unticked once their label lands, and only their own row can tick them.
@MainActor
final class HotCacheSelectionTests: XCTestCase {

    private static let caches = "/nonexistent/pare-hot/Library/Caches"
    private let solo = caches + "/Solo"
    private let mixedOne = caches + "/Mixed/one"
    private let mixedTwo = caches + "/Mixed/two"
    private let other = caches + "/Other"

    private var findings: [ScanFinding] {
        [(solo, 100), (mixedOne, 10), (mixedTwo, 20), (other, 5)].map { path, bytes in
            ScanFinding(
                category: .userCaches, riskLevel: .safe, reason: "test", path: path,
                sizeBytes: Int64(bytes), lastUsed: nil, confidence: 0.9
            )
        }
    }

    private func makeModel() -> (ScanSelectionModel, FolderAggregate) {
        let aggregate = FolderRollup.buildAggregate(from: findings)
        var model = ScanSelectionModel()
        model.updateContext(
            aggregate: aggregate,
            findingsByPath: Dictionary(uniqueKeysWithValues: findings.map { ($0.path, $0) }),
            resetToSafeSelection: true
        )
        return (model, aggregate)
    }

    private func row(_ path: String, in aggregate: FolderAggregate) throws -> CategoryFolderRow {
        let id = try XCTUnwrap(aggregate.folderIdByPath[path])
        return try XCTUnwrap(aggregate.rowsByCategory[.userCaches]?.first { $0.id == id })
    }

    // MARK: - Label arrival

    func testHotLabelUnticksUntouchedRowAndTotalsFollow() throws {
        var (model, aggregate) = makeModel()
        XCTAssertEqual(model.selectedBytes, 135)

        model.applyHotPaths([solo])

        XCTAssertFalse(model.isSelected(path: solo))
        XCTAssertEqual(model.selectedBytes, 35)
        XCTAssertEqual(model.selectedCount, 3)
        XCTAssertEqual(model.selectedHotCount, 0)
        XCTAssertEqual(model.folderSelectionState(try row(solo, in: aggregate)), .none)
    }

    func testLabelAfterUserClickKeepsTheirChoice() {
        let cases: [(name: String, clicks: Int, expected: Bool)] = [
            ("unticked by hand", 1, false),
            ("unticked then ticked again", 2, true),
        ]
        for testCase in cases {
            var (model, _) = makeModel()
            for _ in 0..<testCase.clicks { model.togglePath(solo) }

            model.applyHotPaths([solo])

            XCTAssertEqual(model.isSelected(path: solo), testCase.expected, testCase.name)
            XCTAssertEqual(model.selectedHotCount, testCase.expected ? 1 : 0, testCase.name)
        }
    }

    func testFolderRowClickBeforeLabelCountsAsTouched() throws {
        var (model, aggregate) = makeModel()
        let soloRow = try row(solo, in: aggregate)
        model.toggleFolder(soloRow)
        model.toggleFolder(soloRow)

        model.applyHotPaths([solo])

        XCTAssertTrue(model.isSelected(path: solo))
        XCTAssertEqual(model.folderSelectionState(soloRow), .all)
    }

    func testOneClickTicksHotRowAfterLabel() {
        var (model, _) = makeModel()
        model.applyHotPaths([solo])

        model.togglePath(solo)

        XCTAssertTrue(model.isSelected(path: solo))
        XCTAssertEqual(model.selectedBytes, 135)
        XCTAssertEqual(model.selectedHotCount, 1)
    }

    func testUnlabelledRowsKeepTheirSelection() {
        var (model, _) = makeModel()

        model.applyHotPaths([solo])
        model.applyHotPaths([])

        for path in [mixedOne, mixedTwo, other] {
            XCTAssertTrue(model.isSelected(path: path), path)
        }
    }

    func testUnknownPathLabelIsIgnored() {
        var (model, _) = makeModel()

        model.applyHotPaths([Self.caches + "/NotInThisScan"])

        XCTAssertTrue(model.hotPaths.isEmpty)
        XCTAssertEqual(model.selectedBytes, 135)
    }

    func testHotMemberOfSelectedFolderIsLeftOutOfCleanAndTotals() throws {
        var (model, aggregate) = makeModel()

        model.applyHotPaths([mixedOne])

        XCTAssertFalse(model.isSelected(path: mixedOne))
        XCTAssertTrue(model.isSelected(path: mixedTwo))
        XCTAssertEqual(model.selectedBytes, 125)
        XCTAssertEqual(model.folderSelectionState(try row(mixedOne, in: aggregate)), .partial)
        let toClean = model.selectedFindingPaths(pathsByFolderId: aggregate.pathsByFolderId)
        XCTAssertEqual(toClean, [solo, mixedTwo, other])
    }

    // MARK: - Bulk actions

    func testSelectAllSafeAndCategoryToggleNeverTickHot() {
        var (model, aggregate) = makeModel()
        model.applyHotPaths([solo, mixedOne])
        model.clear()

        model.selectAllSafe()
        XCTAssertFalse(model.isSelected(path: solo))
        XCTAssertFalse(model.isSelected(path: mixedOne))
        XCTAssertTrue(model.isSelected(path: mixedTwo))
        XCTAssertEqual(model.selectionState(of: aggregate.safeFolderIds), .all)

        model.clear()
        model.toggleFolderIds(model.safeFolderIds(in: .userCaches))
        XCTAssertFalse(model.isSelected(path: solo))
        XCTAssertFalse(model.isSelected(path: mixedOne))
        XCTAssertEqual(model.selectedBytes, 25)
    }

    func testSelectAllSafeKeepsHotRowsTheUserTicked() {
        var (model, _) = makeModel()
        model.applyHotPaths([solo, mixedOne])
        model.togglePath(solo)
        model.togglePath(mixedOne)

        model.selectAllSafe()

        XCTAssertTrue(model.isSelected(path: solo))
        XCTAssertTrue(model.isSelected(path: mixedOne))
        XCTAssertEqual(model.selectedBytes, 135)
    }

    func testAllHotFolderRowTogglesItsOwnMember() throws {
        var (model, aggregate) = makeModel()
        model.applyHotPaths([solo])
        let soloRow = try row(solo, in: aggregate)

        model.toggleFolder(soloRow)
        XCTAssertTrue(model.isSelected(path: solo))
        XCTAssertEqual(model.folderSelectionState(soloRow), .all)

        model.toggleFolder(soloRow)
        XCTAssertFalse(model.isSelected(path: solo))
        XCTAssertEqual(model.folderSelectionState(soloRow), .none)
    }

    func testBulkUntickAlsoDropsTickedHotMembers() {
        var (model, _) = makeModel()
        model.applyHotPaths([mixedOne])
        model.togglePath(mixedOne)

        model.toggleFolderIds(model.safeFolderIds(in: .userCaches))

        XCTAssertFalse(model.isSelected(path: mixedOne))
        XCTAssertEqual(model.selectedCount, 0)
    }

    func testNewScanForgetsHotRows() {
        var (model, aggregate) = makeModel()
        model.applyHotPaths([solo])

        model.updateContext(
            aggregate: aggregate,
            findingsByPath: Dictionary(uniqueKeysWithValues: findings.map { ($0.path, $0) }),
            resetToSafeSelection: true
        )

        XCTAssertTrue(model.hotPaths.isEmpty)
        XCTAssertTrue(model.isSelected(path: solo))
    }

    // MARK: - Dashboard view model

    private var report: ScanReport {
        ScanReport(findings: findings, summaries: [ScanCategorySummary(category: .userCaches, reclaimableBytes: 135, fileCount: 4)])
    }

    private let hot = CacheActivityLabel(activity: .hot, newestEntryDate: Date())

    func testLabelsFromAnOlderScanDoNotTouchTheNewSelection() {
        let vm = ScanDashboardViewModel()
        vm.applySnapshotResults(report)
        let staleGeneration = vm.currentScanGeneration
        vm.cancelScan()
        vm.applySnapshotResults(report)

        vm.applyCacheActivity([solo: hot], generation: staleGeneration)
        XCTAssertTrue(vm.isSelected(path: solo))
        XCTAssertNil(vm.cacheActivityText(path: solo))
        XCTAssertEqual(vm.selectedCandidatesBytes, 135)

        vm.applyCacheActivity([solo: hot], generation: vm.currentScanGeneration)
        XCTAssertFalse(vm.isSelected(path: solo))
        XCTAssertEqual(vm.selectedCandidatesBytes, 35)
    }

    func testConfirmationNoticeAppearsOnlyWhenAHotRowIsTicked() {
        let vm = ScanDashboardViewModel()
        vm.applySnapshotResults(report, cacheActivity: [solo: hot])
        XCTAssertNil(vm.hotSelectionNotice)

        vm.toggleSelection(path: solo)

        XCTAssertEqual(
            vm.hotSelectionNotice,
            "1 item was written to in the last 3 days, so its app will download or rebuild it again."
        )
    }

    func testQuickCleanLeavesHotRowsOutAndSaysSo() {
        let vm = ScanDashboardViewModel()
        vm.applySnapshotResults(report)
        XCTAssertEqual(vm.quickCleanCandidatesCount, 4)
        XCTAssertNil(vm.heldOutHotNotice(includeReview: false))

        vm.applyCacheActivity([solo: hot], generation: vm.currentScanGeneration)

        XCTAssertEqual(vm.quickCleanCandidatesCount, 3)
        XCTAssertEqual(vm.quickCleanCandidatesBytes, 35)
        XCTAssertNotNil(vm.heldOutHotNotice(includeReview: false))
    }
}
