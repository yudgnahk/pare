import XCTest
import PareCore
@testable import PareApp

/// Builds of projects edited in the last 3 days start unticked and stay out of Quick, Deep and bulk actions.
@MainActor
final class ActiveProjectSelectionTests: XCTestCase {

    private static let home = "/nonexistent/pare-active/home"
    private let shopRoot = home + "/Code/shop"
    private let blogRoot = home + "/Code/blog"
    private let shopNext = home + "/Code/shop/.next"
    private let shopModules = home + "/Code/shop/node_modules"
    private let blogTarget = home + "/Code/blog/target"
    private let npm = home + "/.npm/_cacache/a"

    private var findings: [ScanFinding] {
        [
            finding(.projectArtifacts, .safe, shopNext, 300),
            finding(.projectArtifacts, .review, shopModules, 500),
            finding(.projectArtifacts, .safe, blogTarget, 200),
            finding(.developerPackageCaches, .safe, npm, 100),
        ]
    }

    private var report: ScanReport {
        let summaries = Dictionary(grouping: findings, by: \.category).map { category, items in
            ScanCategorySummary(
                category: category, reclaimableBytes: items.reduce(0) { $0 + $1.sizeBytes }, fileCount: items.count
            )
        }
        return ScanReport(findings: findings, summaries: summaries)
    }

    private var inputs: OwnerInputs {
        OwnerInputs(
            homeDirectory: URL(fileURLWithPath: Self.home),
            installedApps: .empty,
            registeredRoots: [URL(fileURLWithPath: Self.home + "/Code")],
            probe: SnapshotFixtures.FixtureProjectProbe(gitRoots: [shopRoot, blogRoot], markerRoots: [])
        )
    }

    private func ago(hours: Double) -> ProjectActivityLabel {
        ProjectActivityLabel(newestEditDate: Date().addingTimeInterval(-hours * 3_600))
    }

    private var shopActiveBlogIdle: [String: ProjectActivityLabel] {
        [shopRoot: ago(hours: 1), blogRoot: ago(hours: 5 * 24)]
    }

    private let hotCache = CacheActivityLabel(activity: .hot, newestEntryDate: Date())

    private func makeModel(
        projectLabeler: @escaping @Sendable ([String]) async -> [String: ProjectActivityLabel] = { _ in [:] },
        growthDir: URL? = nil
    ) -> ScanDashboardViewModel {
        let vm = ScanDashboardViewModel(
            growthStore: GrowthSnapshotStore(
                directory: growthDir ?? FileManager.default.temporaryDirectory.appendingPathComponent("pare-active-\(UUID().uuidString)")
            ),
            cacheActivityLabeler: { _ in [:] },
            projectActivityLabeler: projectLabeler
        )
        vm.applySnapshotResults(report, owners: inputs)
        return vm
    }

    private func labelled(_ labels: [String: ProjectActivityLabel]) -> ScanDashboardViewModel {
        let vm = makeModel()
        vm.applyProjectActivity(labels, generation: vm.currentScanGeneration)
        return vm
    }

    private func group(_ root: String, in vm: ScanDashboardViewModel) throws -> OwnerGroup {
        try XCTUnwrap(vm.ownerSections.flatMap(\.groups).first { $0.owner.key == "project:" + root }, root)
    }

    private func folderId(_ path: String, in vm: ScanDashboardViewModel) throws -> String {
        let rows = vm.ownerSections.flatMap(\.groups).flatMap(\.rows)
        return try XCTUnwrap(rows.first { path == $0.row.folderPath || path.hasPrefix($0.row.folderPath + "/") }?.id, path)
    }

    // MARK: - Selection

    func testActiveProjectBuildsStartUntickedAndIdleOnesStayTicked() {
        let vm = labelled(shopActiveBlogIdle)

        XCTAssertFalse(vm.isSelected(path: shopNext))
        XCTAssertTrue(vm.isSelected(path: blogTarget))
        XCTAssertTrue(vm.isSelected(path: npm))
        XCTAssertEqual(vm.selectedCandidatesBytes, 300)
    }

    func testProjectIdleForFiveDaysIsTicked() {
        let vm = labelled([shopRoot: ago(hours: 5 * 24), blogRoot: ago(hours: 5 * 24)])

        XCTAssertTrue(vm.isSelected(path: shopNext))
        XCTAssertTrue(vm.isSelected(path: blogTarget))
        XCTAssertEqual(vm.selectedCandidatesBytes, 600)
    }

    func testUnknownActivityCountsAsActive() {
        let unreadable = ProjectActivityLabel(newestEditDate: nil)
        let cases: [(name: String, labels: [String: ProjectActivityLabel])] = [
            ("budget spent or unreadable", [shopRoot: unreadable, blogRoot: unreadable]),
            ("no label at all", [:]),
        ]
        for testCase in cases {
            let vm = labelled(testCase.labels)

            XCTAssertFalse(vm.isSelected(path: shopNext), testCase.name)
            XCTAssertFalse(vm.isSelected(path: blogTarget), testCase.name)
            XCTAssertTrue(vm.isSelected(path: npm), testCase.name)
        }
    }

    func testRowTheUserClickedKeepsItsState() {
        let cases: [(name: String, clicks: Int, expected: Bool)] = [
            ("unticked by hand", 1, false),
            ("unticked then ticked again", 2, true),
        ]
        for testCase in cases {
            let vm = makeModel()
            for _ in 0..<testCase.clicks { vm.toggleSelection(path: shopNext) }

            vm.applyProjectActivity(shopActiveBlogIdle, generation: vm.currentScanGeneration)

            XCTAssertEqual(vm.isSelected(path: shopNext), testCase.expected, testCase.name)
        }
    }

    func testOneClickTicksAHeldBuild() {
        let vm = labelled(shopActiveBlogIdle)

        vm.toggleSelection(path: shopNext)

        XCTAssertTrue(vm.isSelected(path: shopNext))
        XCTAssertEqual(vm.selectedCandidatesBytes, 600)
    }

    func testLabelsFromAnOlderScanDoNotTouchTheNewSelection() {
        let vm = makeModel()
        let staleGeneration = vm.currentScanGeneration
        vm.cancelScan()
        vm.applySnapshotResults(report, owners: inputs)

        vm.applyProjectActivity(shopActiveBlogIdle, generation: staleGeneration)

        XCTAssertTrue(vm.isSelected(path: shopNext))
        XCTAssertEqual(vm.heldOutProjectCount(includeReview: true), 0)
        XCTAssertEqual(vm.selectedCandidatesBytes, 600)

        vm.applyProjectActivity(shopActiveBlogIdle, generation: vm.currentScanGeneration)
        XCTAssertFalse(vm.isSelected(path: shopNext))
    }

    // MARK: - Bulk actions

    func testQuickDeepAndSelectedCleansLeaveHeldBuildsOut() throws {
        let vm = labelled(shopActiveBlogIdle)

        XCTAssertEqual(vm.quickCleanCandidatesCount, 2)
        for kind in [PendingCleanup.quick, .deep, .selected] {
            let paths = try XCTUnwrap(vm.findingsToClean(for: kind)).map(\.path)
            XCTAssertEqual(Set(paths), [blogTarget, npm], "\(kind)")
        }
    }

    func testSelectAllSafeAndGroupTickNeverTickHeldBuilds() throws {
        let vm = labelled(shopActiveBlogIdle)
        vm.clearSelection()

        vm.selectAllSafe()
        XCTAssertFalse(vm.isSelected(path: shopNext))

        vm.clearSelection()
        vm.toggleOwnerGroup(try group(shopRoot, in: vm))
        XCTAssertFalse(vm.isSelected(path: shopNext))
        XCTAssertEqual(vm.selectedCandidatesCount, 0)
    }

    // MARK: - Clean hold

    func testCleanWaitsOnASlowProjectLabelerThenExcludesActiveProjects() async throws {
        let gate = ProjectLabelerGate()
        let labels = shopActiveBlogIdle
        let growthDir = FileManager.default.temporaryDirectory.appendingPathComponent("pare-active-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: growthDir) }
        let vm = makeModel(
            projectLabeler: { _ in
                await gate.holdUntilReleased()
                return labels
            },
            growthDir: growthDir
        )
        XCTAssertTrue(vm.canRequestCleanup)

        let generation = vm.currentScanGeneration
        let scanReport = report
        let post = Task { await vm.publishPostScanDetails(report: scanReport, generation: generation) }
        await gate.waitUntilHeld()

        XCTAssertFalse(vm.canRequestCleanup)
        for kind in [PendingCleanup.quick, .deep, .selected] {
            XCTAssertNil(vm.findingsToClean(for: kind), "\(kind)")
        }

        await gate.release()
        await post.value

        XCTAssertTrue(vm.canRequestCleanup)
        XCTAssertFalse(vm.isSelected(path: shopNext))
        for kind in [PendingCleanup.quick, .deep, .selected] {
            let paths = try XCTUnwrap(vm.findingsToClean(for: kind)).map(\.path)
            XCTAssertEqual(Set(paths), [blogTarget, npm], "\(kind)")
        }
    }

    // MARK: - Copy

    func testProjectActivityTextAppearsOnlyOnceKnown() throws {
        let vm = makeModel()
        XCTAssertNil(vm.projectActivityText(for: try group(shopRoot, in: vm).owner))

        vm.applyProjectActivity(
            [shopRoot: ago(hours: 1), blogRoot: ago(hours: 5 * 24 + 1)], generation: vm.currentScanGeneration
        )

        XCTAssertEqual(vm.projectActivityText(for: try group(shopRoot, in: vm).owner), "Active today")
        XCTAssertEqual(vm.projectActivityText(for: try group(blogRoot, in: vm).owner), "Idle 5 days")
    }

    func testHeldRowsShowWhyAndOthersDoNot() throws {
        let vm = makeModel()
        XCTAssertNil(vm.holdReason(forFolderId: try folderId(shopNext, in: vm)))

        vm.applyProjectActivity(shopActiveBlogIdle, generation: vm.currentScanGeneration)
        vm.applyCacheActivity([npm: hotCache], generation: vm.currentScanGeneration)

        XCTAssertEqual(vm.holdReason(forFolderId: try folderId(shopNext, in: vm)), "Edited in the last 3 days")
        XCTAssertEqual(vm.holdReason(forFolderId: try folderId(shopModules, in: vm)), "Edited in the last 3 days")
        XCTAssertNil(vm.holdReason(forFolderId: try folderId(blogTarget, in: vm)))
        let npmId = try XCTUnwrap(vm.ownerSections.flatMap(\.groups).flatMap(\.rows).first { npm.hasPrefix($0.row.folderPath) }?.id)
        XCTAssertEqual(vm.holdReason(forFolderId: npmId), "Written to recently")
    }

    func testGroupWhoseSafeRowsAreAllHeldSaysSo() throws {
        let vm = labelled(shopActiveBlogIdle)

        XCTAssertEqual(
            vm.groupHoldReason(safeFolderIds: try group(shopRoot, in: vm).safeFolderIds),
            "Held out: Edited in the last 3 days"
        )
        XCTAssertNil(vm.groupHoldReason(safeFolderIds: try group(blogRoot, in: vm).safeFolderIds))
        XCTAssertNil(vm.groupHoldReason(safeFolderIds: []))
    }

    func testSheetLineCountsHeldBuildsAndLeavesCachesToTheirOwnLine() {
        let vm = makeModel()
        XCTAssertNil(vm.heldOutProjectNotice(includeReview: false))

        vm.applyProjectActivity(shopActiveBlogIdle, generation: vm.currentScanGeneration)
        vm.applyCacheActivity([npm: hotCache], generation: vm.currentScanGeneration)

        XCTAssertEqual(vm.heldOutProjectCount(includeReview: false), 1)
        XCTAssertEqual(vm.heldOutProjectNotice(includeReview: false), "1 build is from a project edited in the last 3 days.")
        XCTAssertEqual(vm.heldOutProjectNotice(includeReview: true), "2 builds are from projects edited in the last 3 days.")
        XCTAssertEqual(vm.heldOutHotCount(includeReview: true), 1)
    }

    // MARK: - Helpers

    private func finding(_ category: ScanCategory, _ risk: RiskLevel, _ path: String, _ bytes: Int64) -> ScanFinding {
        ScanFinding(
            category: category, riskLevel: risk, reason: "test", path: path, sizeBytes: bytes,
            lastUsed: nil, confidence: 1
        )
    }
}

/// Suspends a stub project labeler until the test releases it.
private actor ProjectLabelerGate {
    private var isHeld = false
    private var isReleased = false
    private var waiter: CheckedContinuation<Void, Never>?

    func holdUntilReleased() async {
        isHeld = true
        guard !isReleased else { return }
        await withCheckedContinuation { waiter = $0 }
    }

    func waitUntilHeld() async {
        while !isHeld { await Task.yield() }
    }

    func release() {
        isReleased = true
        waiter?.resume()
        waiter = nil
    }
}
