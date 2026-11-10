import AppKit
import XCTest
import PareCore
@testable import PareApp

/// The clean list, owner chips and fold rows are views of the same folder rows: no bulk tick may reach
/// review, hot, advanced or explain-only rows, and nothing here may change what a clean would trash.
@MainActor
final class CleanListBrowseTests: XCTestCase {

    private static let home = "/nonexistent/pare-clean-list/home"
    private static let mb: Int64 = 1_000_000
    private let chromeCache = home + "/Library/Caches/Google/Chrome/Default/Cache/f1"
    private let chromeSite = home + "/Library/Application Support/Google/Chrome/Default/Local Storage/x"
    private let small = home + "/Library/Caches/com.acme.small/blob"
    private let smallHot = home + "/Library/Caches/com.acme.hot/blob"
    private let crashLog = home + "/Library/Logs/DiagnosticReports/r.ips"
    private let npm = home + "/.npm/_cacache/a"
    private let shopNext = home + "/Code/shop/.next"
    private let shopModules = home + "/Code/shop/node_modules"
    private let installer = home + "/Downloads/Setup.dmg"
    private let goModules = home + "/go/pkg/mod/x"
    private let swap = "/private/var/vm"
    private let chromeApp = URL(fileURLWithPath: "/nonexistent/pare-clean-list/Applications/Google Chrome.app")

    private var findings: [ScanFinding] {
        [
            finding(.browserCaches, .safe, chromeCache, 200 * Self.mb),
            finding(.browserCaches, .review, chromeSite, 3_000 * Self.mb),
            finding(.userCaches, .safe, small, 10 * Self.mb),
            finding(.userCaches, .safe, smallHot, 20 * Self.mb),
            finding(.logsAndCrashReports, .safe, crashLog, 5 * Self.mb),
            finding(.developerPackageCaches, .safe, npm, 500 * Self.mb),
            finding(.projectArtifacts, .safe, shopNext, 300 * Self.mb),
            finding(.projectArtifacts, .review, shopModules, 800 * Self.mb),
            finding(.installerFiles, .review, installer, 30 * Self.mb),
            finding(.developerPackageCaches, .advanced, goModules, 4_000 * Self.mb),
            ScanFinding(
                category: .diagnostics, riskLevel: .advanced, reason: "swap", path: swap, sizeBytes: 999,
                lastUsed: nil, confidence: 1, annotations: [.explainOnly(action: "Restart")]
            ),
        ]
    }

    private var report: ScanReport { ScanReport(findings: findings, summaries: []) }

    private var inputs: OwnerInputs {
        OwnerInputs(
            homeDirectory: URL(fileURLWithPath: Self.home),
            installedApps: InstalledAppIndex(
                namesByBundleID: ["com.google.chrome": "Google Chrome"],
                appURLsByBundleID: ["com.google.chrome": chromeApp]
            ),
            registeredRoots: [URL(fileURLWithPath: Self.home + "/Code")],
            probe: SnapshotFixtures.FixtureProjectProbe(gitRoots: [Self.home + "/Code/shop"], markerRoots: [])
        )
    }

    private func loaded() -> ScanDashboardViewModel {
        let vm = ScanDashboardViewModel()
        vm.applySnapshotResults(report, owners: inputs)
        return vm
    }

    private func markHot(_ path: String, in vm: ScanDashboardViewModel) {
        vm.applyCacheActivity(
            [path: CacheActivityLabel(activity: .hot, newestEntryDate: Date())], generation: vm.currentScanGeneration
        )
    }

    private func section(_ group: CleanCategory, in vm: ScanDashboardViewModel) throws -> CleanSection {
        try XCTUnwrap(vm.cleanSections.first { $0.group == group }, "\(group)")
    }

    private func allRows(_ vm: ScanDashboardViewModel) -> [CleanRow] {
        vm.cleanSections.flatMap { $0.rows + $0.smallRows }
    }

    private func row(_ path: String, in vm: ScanDashboardViewModel) throws -> CleanRow {
        try XCTUnwrap(vm.cleanRows.first {
            path == $0.record.folderPath || path.hasPrefix($0.record.folderPath + "/")
        }, path)
    }

    private func cleanSets(_ vm: ScanDashboardViewModel) throws -> [Set<String>] {
        try [PendingCleanup.quick, .deep, .selected].map { Set(try XCTUnwrap(vm.findingsToClean(for: $0)).map(\.path)) }
    }

    private var reviewPaths: Set<String> { [chromeSite, shopModules, installer] }

    // MARK: - Groups

    func testRowsLandInTheirCleanCategory() throws {
        let vm = loaded()

        XCTAssertEqual(vm.cleanSections.map(\.group), [.appCaches, .developerTools, .projects, .siteData, .oldVersions, .system, .sizeOnly])
        XCTAssertEqual(try row(chromeCache, in: vm).group, .appCaches)
        XCTAssertEqual(try row(small, in: vm).group, .appCaches)
        XCTAssertEqual(try row(crashLog, in: vm).group, .system)
        XCTAssertEqual(try row(npm, in: vm).group, .developerTools)
        XCTAssertEqual(try row(shopNext, in: vm).group, .projects)
        XCTAssertEqual(try row(shopModules, in: vm).group, .projects)
        XCTAssertEqual(try row(chromeSite, in: vm).group, .siteData)
        XCTAssertEqual(try row(installer, in: vm).group, .oldVersions)
        XCTAssertEqual(try row(goModules, in: vm).group, .sizeOnly)
        XCTAssertFalse(vm.cleanRows.contains { $0.record.folderPath.hasPrefix(swap) })
    }

    func testTotalsCoverEveryFolderIncludingFoldedOnes() throws {
        let vm = loaded()
        let aggregate = FolderRollup.buildAggregate(from: findings)
        let ids = vm.cleanSections.flatMap(\.folderIds)
        let reclaimable = findings.filter { $0.riskLevel != .advanced }.reduce(Int64(0)) { $0 + $1.sizeBytes }
        let selectable = vm.cleanSections.filter(\.group.isSelectable)

        XCTAssertEqual(ids.count, Set(ids).count)
        XCTAssertEqual(Set(ids), Set(aggregate.recordsByFolderId.keys))
        XCTAssertEqual(selectable.reduce(Int64(0)) { $0 + $1.totalBytes }, reclaimable)
        XCTAssertEqual(try section(.sizeOnly, in: vm).totalBytes, 4_000 * Self.mb)
        XCTAssertEqual(try section(.appCaches, in: vm).smallBytes, 30 * Self.mb)
        XCTAssertEqual(vm.allChipBytes, reclaimable)
    }

    func testExpansionDefaultsAndToggles() {
        let vm = loaded()

        XCTAssertTrue(vm.isCleanExpanded(.appCaches))
        XCTAssertTrue(vm.isCleanExpanded(.siteData))
        XCTAssertFalse(vm.isCleanExpanded(.sizeOnly))
        XCTAssertFalse(vm.isSmallRowsExpanded(.appCaches))

        vm.toggleCleanExpanded(.appCaches)
        vm.toggleCleanExpanded(.sizeOnly)
        vm.toggleSmallRowsExpanded(.appCaches)

        XCTAssertFalse(vm.isCleanExpanded(.appCaches))
        XCTAssertTrue(vm.isCleanExpanded(.sizeOnly))
        XCTAssertTrue(vm.isSmallRowsExpanded(.appCaches))
    }

    // MARK: - Bulk ticks

    func testGroupTickSelectsSafeIdsOnlyAndUntickRemovesThem() {
        let vm = loaded()
        for section in vm.cleanSections where section.isSelectable {
            vm.clearSelection()

            vm.toggleCleanSection(section)

            XCTAssertEqual(vm.selection.selectedFolderIds, section.safeFolderIds, "\(section.group)")
            XCTAssertEqual(vm.cleanSelectionState(section), .all, "\(section.group)")
            XCTAssertEqual(vm.selectedReviewCount, 0, "\(section.group)")
            XCTAssertTrue(reviewPaths.allSatisfy { !vm.isSelected(path: $0) }, "\(section.group)")

            vm.toggleCleanSection(section)

            XCTAssertTrue(vm.selection.selectedFolderIds.isEmpty, "\(section.group)")
        }
    }

    func testCategoriesWithoutSafeRowsTickNothingInBulk() throws {
        let vm = loaded()
        vm.clearSelection()

        for group in [CleanCategory.siteData, .oldVersions, .sizeOnly] {
            let section = try self.section(group, in: vm)
            XCTAssertFalse(section.isSelectable, "\(group)")
            vm.toggleCleanSection(section)
            vm.toggleSmallRows(section)
        }

        XCTAssertEqual(vm.selectedCandidatesCount, 0)
        XCTAssertEqual(vm.cleanSelectHelp(try section(.siteData, in: vm)), "Review items: tick one by one")
        XCTAssertEqual(vm.cleanSelectHelp(try section(.sizeOnly, in: vm)), "Pare won't clean these")
    }

    func testSizeOnlyRowCannotBeTicked() throws {
        let vm = loaded()
        let go = try row(goModules, in: vm)
        let before = vm.selection.selectedFolderIds

        vm.toggleFolder(ScanDashboardViewModel.folderRow(go))

        XCTAssertFalse(ScanDashboardViewModel.folderRow(go).isSelectable)
        XCTAssertEqual(vm.selection.selectedFolderIds, before)
        XCTAssertFalse(try XCTUnwrap(vm.findingsToClean(for: .selected)).map(\.path).contains(goModules))
    }

    func testFoldTickSelectsSmallSafeIdsAndNeverAHotRow() throws {
        let vm = loaded()
        markHot(smallHot, in: vm)
        let apps = try section(.appCaches, in: vm)
        vm.clearSelection()

        XCTAssertEqual(Set(apps.smallRows.map(\.record.folderPath)).count, 2)
        vm.toggleSmallRows(apps)

        XCTAssertTrue(vm.selection.selectedFolderIds.isSubset(of: apps.smallSafeFolderIds))
        XCTAssertTrue(vm.isSelected(path: small))
        XCTAssertFalse(vm.isSelected(path: smallHot))
        XCTAssertFalse(vm.isSelected(path: chromeCache))
        XCTAssertFalse(vm.isSelected(path: crashLog))
        XCTAssertEqual(vm.smallRowsSelectionState(apps), .partial)

        vm.toggleCleanSection(apps)
        XCTAssertFalse(vm.isSelected(path: smallHot))
        XCTAssertTrue(vm.isSelected(path: chromeCache))
    }

    // MARK: - Owner chips

    func testChipFilterShowsOneOwnerAndRecomputesSizes() throws {
        let vm = loaded()

        vm.setOwnerFilter("app:chrome")

        XCTAssertEqual(vm.ownerFilter, "app:chrome")
        XCTAssertTrue(allRows(vm).allSatisfy { $0.owner.key == "app:chrome" })
        XCTAssertEqual(vm.cleanSections.map(\.group), [.appCaches, .siteData])
        XCTAssertEqual(try section(.appCaches, in: vm).totalBytes, 200 * Self.mb)
        XCTAssertEqual(try section(.siteData, in: vm).totalBytes, 3_000 * Self.mb)
        XCTAssertEqual(
            vm.cleanSizeText(try section(.appCaches, in: vm)),
            ScanDashboardViewModel.selectedOfTotal(selected: 200 * Self.mb, total: ScanReportPresenter.formatBytes(200 * Self.mb))
        )
    }

    func testFilteredGroupTickTicksOnlyVisibleSafeIds() throws {
        let vm = loaded()
        let chromeId = try row(chromeCache, in: vm).id
        vm.setOwnerFilter("app:chrome")
        vm.clearSelection()

        vm.toggleCleanSection(try section(.appCaches, in: vm))

        XCTAssertEqual(vm.selection.selectedFolderIds, [chromeId])
        XCTAssertFalse(vm.isSelected(path: chromeSite))
        XCTAssertFalse(vm.isSelected(path: small))
    }

    func testProjectsAndToolsShareOneChipEach() throws {
        let vm = loaded()
        let ids = vm.ownerChips.map(\.id)

        XCTAssertTrue(ids.contains(ScanDashboardViewModel.projectsChipId))
        XCTAssertTrue(ids.contains(ScanDashboardViewModel.toolsChipId))
        XCTAssertEqual(ids.count, Set(ids).count)
        let tools = try XCTUnwrap(vm.ownerChips.first { $0.id == ScanDashboardViewModel.toolsChipId })
        XCTAssertEqual(tools.title, "Dev tools")
        XCTAssertEqual(tools.bytes, 500 * Self.mb, "size-only Go is not reclaimable")
        XCTAssertEqual(vm.ownerChips.map(\.bytes), vm.ownerChips.map(\.bytes).sorted(by: >))

        vm.setOwnerFilter(ScanDashboardViewModel.projectsChipId)
        XCTAssertTrue(allRows(vm).allSatisfy { $0.owner.kind == .project })
        XCTAssertEqual(Set(allRows(vm).map(\.record.folderPath)), [shopNext, shopModules])

        vm.setOwnerFilter(ScanDashboardViewModel.toolsChipId)
        XCTAssertEqual(vm.cleanSections.map(\.group), [.developerTools, .sizeOnly])
    }

    func testChipsSplitIntoTopSixAndMore() {
        let vm = loaded()

        XCTAssertEqual(vm.primaryChips.count, min(vm.ownerChips.count, ScanDashboardViewModel.primaryChipCount))
        XCTAssertEqual(vm.primaryChips + vm.moreChips, vm.ownerChips)
    }

    func testUnknownChipIsIgnored() {
        let vm = loaded()

        vm.setOwnerFilter("app:not-here")

        XCTAssertNil(vm.ownerFilter)
        XCTAssertEqual(vm.cleanSections.count, 7)
    }

    func testSelectionSurvivesFilterChanges() throws {
        let vm = loaded()
        vm.toggleFolder(ScanDashboardViewModel.folderRow(try row(shopModules, in: vm)))
        vm.toggleSelection(path: crashLog)
        let before = vm.selection

        for chip in [ScanDashboardViewModel.toolsChipId, "app:chrome", nil] {
            vm.setOwnerFilter(chip)
            XCTAssertEqual(vm.selection.selectedFolderIds, before.selectedFolderIds, chip ?? "All")
            XCTAssertEqual(vm.selection.selectedPaths, before.selectedPaths, chip ?? "All")
            XCTAssertEqual(vm.selectedCandidatesBytes, before.selectedBytes, chip ?? "All")
        }
    }

    func testFilterResetsOnANewScan() {
        let vm = loaded()
        vm.setOwnerFilter("app:chrome")

        vm.applySnapshotResults(report, owners: inputs)

        XCTAssertNil(vm.ownerFilter)
        XCTAssertEqual(vm.cleanSections.map(\.group), [.appCaches, .developerTools, .projects, .siteData, .oldVersions, .system, .sizeOnly])
    }

    // MARK: - Clean sets

    func testListChangesNeverChangeWhatCleansWouldTrash() throws {
        let vm = loaded()
        markHot(smallHot, in: vm)
        let before = try cleanSets(vm)

        vm.setOwnerFilter(ScanDashboardViewModel.toolsChipId)
        vm.toggleSmallRowsExpanded(.appCaches)
        vm.toggleCleanExpanded(.sizeOnly)
        vm.setOwnerFilter("app:chrome")
        vm.setOwnerFilter(nil)

        XCTAssertEqual(try cleanSets(vm), before)
        XCTAssertEqual(before[0], Set(findings.map(\.path)).subtracting([smallHot]))
        XCTAssertEqual(before[1], before[0])
        XCTAssertEqual(before[2], [chromeCache, small, crashLog, npm, shopNext])
    }

    // MARK: - Headers, rows and cards

    func testHeaderShowsSelectedOverTotal() throws {
        let vm = loaded()
        let format = ScanReportPresenter.formatBytes

        XCTAssertEqual(vm.cleanSizeText(try section(.appCaches, in: vm)), "\(format(230 * Self.mb)) / \(format(230 * Self.mb))")
        XCTAssertEqual(vm.cleanSizeText(try section(.projects, in: vm)), "\(format(300 * Self.mb)) / \(format(1_100 * Self.mb))")
        XCTAssertEqual(vm.cleanSizeText(try section(.siteData, in: vm)), "0 / \(format(3_000 * Self.mb))")
        XCTAssertEqual(vm.cleanSizeText(try section(.sizeOnly, in: vm)), format(4_000 * Self.mb))
        XCTAssertEqual(ScanDashboardViewModel.smallRowsTitle(1), "1 small item")
        XCTAssertEqual(ScanDashboardViewModel.smallRowsTitle(3), "3 small items")
    }

    func testRowTitlesNameTheOwnerAndKind() throws {
        let vm = loaded()

        XCTAssertEqual(ScanDashboardViewModel.rowTitle(try row(chromeCache, in: vm)), "Chrome · cache")
        XCTAssertEqual(ScanDashboardViewModel.rowTitle(try row(chromeSite, in: vm)), "Chrome · site data")
        XCTAssertEqual(ScanDashboardViewModel.rowTitle(try row(shopNext, in: vm)), "shop · .next")
        XCTAssertEqual(ScanDashboardViewModel.rowTitle(try row(npm, in: vm)), "npm · package cache")
        XCTAssertEqual(ScanDashboardViewModel.rowTitle(try row(small, in: vm)), "com.acme.small · cache")
    }

    func testHeldRowSubtitleCarriesTheReason() throws {
        let vm = loaded()
        markHot(smallHot, in: vm)
        let hot = try row(smallHot, in: vm)
        let reason = try XCTUnwrap(vm.holdReason(forFolderId: hot.id))

        XCTAssertEqual(vm.rowSubtitle(hot), FolderRollup.abbreviatePath(hot.record.folderPath) + " · " + reason)
        XCTAssertEqual(vm.rowSubtitle(try row(small, in: vm)), FolderRollup.abbreviatePath(try row(small, in: vm).record.folderPath))
    }

    func testAppOwnersGetTheirInstalledIconPath() throws {
        let vm = loaded()

        XCTAssertEqual(vm.appIconPath(for: try row(chromeCache, in: vm).owner), chromeApp.path)
        XCTAssertNil(vm.appIconPath(for: try row(npm, in: vm).owner))
        XCTAssertNil(vm.appIconPath(for: try row(shopNext, in: vm).owner))
    }

    func testIconCacheLoadsEachPathOnce() {
        var loads: [String] = []
        let cache = AppIconCache(loader: { path in
            loads.append(path)
            return NSImage(size: NSSize(width: 1, height: 1))
        })

        _ = cache.icon(forPath: "/a.app")
        _ = cache.icon(forPath: "/a.app")
        _ = cache.icon(forPath: "/b.app")

        XCTAssertEqual(loads, ["/a.app", "/b.app"])
        XCTAssertNotNil(cache.cachedIcon(forPath: "/a.app"))
        XCTAssertNil(cache.cachedIcon(forPath: "/c.app"))
    }

    func testHeroLineCountsEverythingFoundAndHowManyAreHeld() {
        let vm = loaded()
        markHot(smallHot, in: vm)
        let format = ScanReportPresenter.formatBytes

        XCTAssertEqual(vm.foundCandidateStats.safeCount, 6)
        XCTAssertEqual(vm.foundCandidateStats.safeBytes, 1_035 * Self.mb)
        XCTAssertEqual(vm.foundCandidateStats.reviewBytes, 3_830 * Self.mb)
        XCTAssertEqual(vm.quickCleanCandidatesCount, 5)
        XCTAssertEqual(vm.heldSafeCount, 1)
        XCTAssertEqual(
            vm.heroSummaryLine,
            "of \(format(4_865 * Self.mb)) found · \(format(1_035 * Self.mb)) safe · \(format(3_830 * Self.mb)) needs review"
                + " · 1 held back — used or edited in the last 3 days"
        )
    }

    func testHeroLineLeavesOutZeroParts() {
        let safeOnly = CandidateStats(safeCount: 2, safeBytes: 5_000, reviewCount: 0, reviewBytes: 0)
        let format = ScanReportPresenter.formatBytes

        XCTAssertEqual(
            ScanDashboardViewModel.heroSummaryLine(stats: safeOnly, heldCount: 0, isPartial: false),
            "of \(format(5_000)) found · \(format(5_000)) safe"
        )
        XCTAssertEqual(
            ScanDashboardViewModel.heroSummaryLine(stats: CandidateStats(), heldCount: 0, isPartial: true),
            "of ≥ \(format(0)) found"
        )
    }

    func testHeroNumberIsWhatTheCleanBarSelects() throws {
        let vm = loaded()
        vm.toggleFolder(ScanDashboardViewModel.folderRow(try row(npm, in: vm)))

        XCTAssertEqual(vm.selectedCandidatesBytes, vm.selection.selectedBytes)
        XCTAssertEqual(vm.selectedCandidatesBytes, (200 + 10 + 20 + 5 + 300) * Self.mb)
    }

    // MARK: - Helpers

    private func finding(_ category: ScanCategory, _ risk: RiskLevel, _ path: String, _ bytes: Int64) -> ScanFinding {
        ScanFinding(
            category: category, riskLevel: risk, reason: "test", path: path, sizeBytes: bytes,
            lastUsed: nil, confidence: 1
        )
    }
}
