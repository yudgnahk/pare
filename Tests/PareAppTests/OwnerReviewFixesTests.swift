import XCTest
import PareCore
@testable import PareApp

/// Review fixes for the owner browser: same-name projects, exclusion, rollback, wait box, copy and labels.
@MainActor
final class OwnerReviewFixesTests: XCTestCase {

    private static let home = "/nonexistent/pare-review/home"
    private let apiA = home + "/Code/a/api"
    private let apiB = home + "/Code/b/api"

    private var findings: [ScanFinding] {
        [
            finding(.safe, apiA + "/.next", 100),
            finding(.review, apiA + "/node_modules", 300),
            finding(.safe, apiB + "/.next", 200),
            finding(.review, apiB + "/node_modules", 400),
        ]
    }

    private var inputs: OwnerInputs {
        OwnerInputs(
            homeDirectory: URL(fileURLWithPath: Self.home),
            installedApps: .empty,
            registeredRoots: [URL(fileURLWithPath: Self.home + "/Code")],
            probe: SnapshotFixtures.FixtureProjectProbe(gitRoots: [apiA, apiB], markerRoots: [])
        )
    }

    private func loaded(store: ExclusionStore? = nil) -> ScanDashboardViewModel {
        let vm = store.map { ScanDashboardViewModel(browseModes: .inMemory(.categories), exclusionStore: $0) }
            ?? ScanDashboardViewModel(browseModes: .inMemory(.categories))
        let summary = ScanCategorySummary(category: .projectArtifacts, reclaimableBytes: 1_000, fileCount: 4)
        vm.applySnapshotResults(ScanReport(findings: findings, summaries: [summary]), owners: inputs)
        return vm
    }

    private func rowId(_ path: String, in vm: ScanDashboardViewModel) throws -> String {
        let rows = vm.categoryFolderRows[.projectArtifacts] ?? []
        return try XCTUnwrap(rows.first { $0.folderPath == path }?.id, path)
    }

    private func groupHolding(_ path: String, in vm: ScanDashboardViewModel) throws -> CategoryToolGroup {
        let id = try rowId(path, in: vm)
        return try XCTUnwrap(vm.toolGroups(for: .projectArtifacts).first { $0.folderIds.contains(id) }, path)
    }

    // MARK: - Same-name projects in Categories mode

    func testSameNameProjectsStaySeparateGroupsWithOwnSafeIds() throws {
        let vm = loaded()
        let groups = vm.toolGroups(for: .projectArtifacts)
        let a = try groupHolding(apiA + "/.next", in: vm)
        let b = try groupHolding(apiB + "/.next", in: vm)

        XCTAssertEqual(groups.count, 2)
        XCTAssertNotEqual(a.id, b.id)
        XCTAssertEqual(a.safeFolderIds, [try rowId(apiA + "/.next", in: vm)])
        XCTAssertEqual(b.safeFolderIds, [try rowId(apiB + "/.next", in: vm)])
        XCTAssertEqual(a.folderIds.count, 2)
        XCTAssertEqual(b.folderIds.count, 2)
    }

    func testSameNameProjectTitlesShowEnoughPathToTellThemApart() throws {
        let vm = loaded()
        let a = try groupHolding(apiA + "/.next", in: vm)
        let b = try groupHolding(apiB + "/.next", in: vm)

        XCTAssertNotEqual(a.toolName, b.toolName)
        XCTAssertTrue(a.toolName.hasPrefix("api · "))
        XCTAssertTrue(a.toolName.hasSuffix("/Code/a/api"), a.toolName)
        XCTAssertTrue(b.toolName.hasSuffix("/Code/b/api"), b.toolName)
    }

    func testUniquelyNamedProjectKeepsItsPlainName() {
        let one = Array(findings.prefix(2))
        let vm = ScanDashboardViewModel(browseModes: .inMemory(.categories))
        vm.applySnapshotResults(ScanReport(findings: one, summaries: []), owners: inputs)

        XCTAssertEqual(vm.toolGroups(for: .projectArtifacts).map(\.toolName), ["api"])
    }

    func testToolGroupCheckboxTicksOnlyItsOwnProjectsSafeFolders() throws {
        let vm = loaded()
        let a = try groupHolding(apiA + "/.next", in: vm)
        vm.clearSelection()

        vm.toggleToolGroup(a)

        XCTAssertEqual(vm.selection.selectedFolderIds, a.safeFolderIds)
        XCTAssertTrue(vm.isSelected(path: apiA + "/.next"))
        XCTAssertFalse(vm.isSelected(path: apiA + "/node_modules"))
        XCTAssertFalse(vm.isSelected(path: apiB + "/.next"))
        XCTAssertFalse(vm.isSelected(path: apiB + "/node_modules"))
        XCTAssertEqual(vm.selectedReviewCount, 0)
    }

    // MARK: - exclude(path:)

    func testExcludeWritesTheInjectedStoreAndRebuildsGroupsWithSameOwners() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("pare-excl-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = ExclusionStore(fileURL: dir.appendingPathComponent("exclusions.json"))
        let vm = loaded(store: store)
        let before = vm.totalReclaimableBytes
        let excluded = apiB + "/.next"

        vm.exclude(path: excluded)

        let saved = try store.load()
        XCTAssertTrue(saved.isExcluded(excluded))
        XCTAssertFalse(saved.isExcluded(apiA + "/.next"))
        XCTAssertEqual(before, 1_000)
        XCTAssertEqual(vm.totalReclaimableBytes, 800)
        XCTAssertFalse(vm.latestFindingsSnapshot.contains { $0.path == excluded })
        let groups = vm.ownerSections.flatMap(\.groups)
        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(Set(groups.map(\.owner.key)), ["project:" + apiA, "project:" + apiB])
        let rebuiltB = try XCTUnwrap(groups.first { $0.owner.key == "project:" + apiB })
        XCTAssertEqual(rebuiltB.rows.map(\.row.folderPath), [apiB + "/node_modules"])
        XCTAssertTrue(rebuiltB.safeFolderIds.isEmpty)
        XCTAssertEqual(vm.toolGroups(for: .projectArtifacts).count, 2)
    }

    // MARK: - Rollback (owner view off)

    func testNilResolverKeepsLegacyLabelsAndPerFindingDonut() {
        let base = FolderRollup.buildAggregate(from: findings)

        let result = ScanDashboardViewModel.ownerResults(aggregate: base, findings: findings, resolver: nil)

        XCTAssertTrue(result.sections.isEmpty)
        XCTAssertTrue(result.ownerByFolderPath.isEmpty)
        XCTAssertEqual(result.aggregate.rowsByCategory, base.rowsByCategory)
        XCTAssertEqual(result.aggregate.toolGroupsByCategory, base.toolGroupsByCategory)
        XCTAssertEqual(result.toolRollups, FolderRollup.makeToolRollups(from: findings))
    }

    func testOwnerViewFlagAgreesWithTheViewModel() {
        let vm = ScanDashboardViewModel(browseModes: .inMemory(.apps))

        XCTAssertEqual(vm.isOwnerViewEnabled, SmartScanFeatures.ownerView)
        XCTAssertEqual(vm.browseMode, SmartScanFeatures.ownerView ? .apps : .categories)
    }

    // MARK: - TimeBoxedValue

    func testSeveralWaitersAllReceiveTheValue() async {
        let box = TimeBoxedValue<Int>()
        Task.detached {
            try? await Task.sleep(nanoseconds: 50_000_000)
            box.fulfill(9)
        }

        async let first = box.value(waitingAtMost: 5)
        async let second = box.value(waitingAtMost: 5)
        let values = await [first, second]

        XCTAssertEqual(values, [9, 9])
    }

    func testSeveralWaitersAllTimeOut() async {
        let box = TimeBoxedValue<Int>()

        async let first = box.value(waitingAtMost: 0.05)
        async let second = box.value(waitingAtMost: 0.05)
        let values = await [first, second]

        XCTAssertEqual(values, [nil, nil])
    }

    func testCancelFlagIsVisibleToTheProducer() {
        let box = TimeBoxedValue<Int>()
        XCTAssertFalse(box.isCancelled)

        box.cancel()

        XCTAssertTrue(box.isCancelled)
    }

    // MARK: - Copy and accessibility

    func testEmptyMessageNamesTheActiveMode() {
        XCTAssertEqual(BrowseModeSwitch.emptyMessage(byApp: true), "Start a scan to browse reclaimable storage by app.")
        XCTAssertEqual(BrowseModeSwitch.emptyMessage(byApp: false), "Start a scan to browse reclaimable storage by category.")
    }

    func testBrowseModeButtonsHaveDistinctLabels() {
        let labels = BrowseMode.allCases.map(BrowseModeSwitch.accessibilityLabel)

        XCTAssertEqual(labels, ["Browse by app", "Browse by category"])
    }

    func testCheckboxLabelsNameTheGroupAndState() {
        XCTAssertEqual(SelectAccessibility.groupLabel(title: "Chrome"), "Select safe folders in Chrome")
        XCTAssertEqual(SelectAccessibility.folderLabel(path: "~/.npm"), "Select ~/.npm")
        XCTAssertEqual(SelectAccessibility.stateText(.all), "Selected")
        XCTAssertEqual(SelectAccessibility.stateText(.partial), "Partly selected")
        XCTAssertEqual(SelectAccessibility.stateText(.none), "Not selected")
    }

    private func finding(_ risk: RiskLevel, _ path: String, _ bytes: Int64) -> ScanFinding {
        ScanFinding(
            category: .projectArtifacts, riskLevel: risk, reason: "test", path: path, sizeBytes: bytes,
            lastUsed: nil, confidence: 1
        )
    }
}
