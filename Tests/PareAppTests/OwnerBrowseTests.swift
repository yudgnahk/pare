import AppKit
import XCTest
import PareCore
@testable import PareApp

/// The owner browser is another view of the same folder rows: it must never change what is selected or cleaned.
@MainActor
final class OwnerBrowseTests: XCTestCase {

    private static let home = "/nonexistent/pare-owner/home"
    private let chromeCache = home + "/Library/Caches/Google/Chrome/Default/Cache/f1"
    private let chromeStorage = home + "/Library/Application Support/Google/Chrome/Default/Local Storage/x"
    private let npmA = home + "/.npm/_cacache/a"
    private let npmB = home + "/.npm/_cacache/b"
    private let shopNext = home + "/Code/shop/.next"
    private let shopModules = home + "/Code/shop/node_modules"
    private let crashLog = home + "/Library/Logs/DiagnosticReports/r.ips"
    private let partialApp = home + "/Library/Caches/com.acme.W/blob"
    private let installer = home + "/Downloads/Setup.dmg"
    private let goModules = home + "/go/pkg/mod/x"
    private let swap = "/private/var/vm"

    private var findings: [ScanFinding] {
        [
            finding(.browserCaches, .safe, chromeCache, 100),
            finding(.browserCaches, .review, chromeStorage, 40),
            finding(.developerPackageCaches, .safe, npmA, 200),
            finding(.developerPackageCaches, .safe, npmB, 50),
            finding(.projectArtifacts, .safe, shopNext, 300),
            finding(.projectArtifacts, .review, shopModules, 500),
            finding(.logsAndCrashReports, .safe, crashLog, 10),
            finding(.userCaches, .safe, partialApp, 60, complete: false),
            finding(.installerFiles, .review, installer, 70),
            finding(.developerPackageCaches, .advanced, goModules, 777),
            ScanFinding(
                category: .diagnostics, riskLevel: .advanced, reason: "swap", path: swap, sizeBytes: 999,
                lastUsed: nil, confidence: 1, annotations: [.explainOnly(action: "Restart")]
            ),
        ]
    }

    private var report: ScanReport {
        let grouped = Dictionary(grouping: findings, by: \.category)
        let summaries = grouped.map { category, items in
            ScanCategorySummary(
                category: category,
                reclaimableBytes: items.filter { $0.riskLevel != .advanced }.reduce(0) { $0 + $1.sizeBytes },
                fileCount: items.count
            )
        }
        return ScanReport(findings: findings, summaries: summaries)
    }

    private var inputs: OwnerInputs {
        OwnerInputs(
            homeDirectory: URL(fileURLWithPath: Self.home),
            installedApps: InstalledAppIndex(namesByBundleID: ["com.acme.w": "W"]),
            registeredRoots: [URL(fileURLWithPath: Self.home + "/Code")],
            probe: SnapshotFixtures.FixtureProjectProbe(gitRoots: [Self.home + "/Code/shop"], markerRoots: [])
        )
    }

    private func loaded(mode: BrowseMode = .apps, store: BrowseModeStore? = nil) -> ScanDashboardViewModel {
        let vm = ScanDashboardViewModel(browseModes: store ?? .inMemory(mode))
        vm.applySnapshotResults(report, owners: inputs)
        return vm
    }

    private func group(_ key: String, in vm: ScanDashboardViewModel) throws -> OwnerGroup {
        try XCTUnwrap(vm.ownerSections.flatMap(\.groups).first { $0.owner.key == key }, key)
    }

    private func folderId(_ path: String, in vm: ScanDashboardViewModel) throws -> String {
        let rows = vm.ownerSections.flatMap(\.groups).flatMap(\.rows)
        return try XCTUnwrap(rows.first { path == $0.row.folderPath || path.hasPrefix($0.row.folderPath + "/") }?.id, path)
    }

    // MARK: - Mode switch

    func testSwitchingModeKeepsSelectionIdentical() throws {
        let vm = loaded()
        vm.toggleFolder(try XCTUnwrap(vm.ownerSections.flatMap(\.groups).flatMap(\.rows).first { $0.row.folderPath == shopModules }).row)
        vm.toggleSelection(path: crashLog)
        let before = vm.selection

        for mode in [BrowseMode.categories, .apps, .categories] {
            vm.setBrowseMode(mode)
            XCTAssertEqual(vm.browseMode, mode)
            XCTAssertEqual(vm.selection.selectedFolderIds, before.selectedFolderIds, "\(mode)")
            XCTAssertEqual(vm.selection.selectedPaths, before.selectedPaths, "\(mode)")
            XCTAssertEqual(vm.selection.selectedBytes, before.selectedBytes, "\(mode)")
            XCTAssertEqual(vm.selection.selectedCount, before.selectedCount, "\(mode)")
        }
    }

    func testPostScanSelectionIsEverySafeFolderInEitherMode() {
        let expected = FolderRollup.buildAggregate(from: findings).safeFolderIds
        for mode in BrowseMode.allCases {
            let vm = loaded(mode: mode)
            let ownerSafe = vm.ownerSections.flatMap(\.groups).reduce(into: Set<String>()) { $0.formUnion($1.safeFolderIds) }

            XCTAssertEqual(vm.browseMode, mode)
            XCTAssertEqual(vm.selection.selectedFolderIds, expected, "\(mode)")
            XCTAssertEqual(ownerSafe, expected, "\(mode)")
        }
    }

    func testTotalsStatsAndCleanSetsDoNotDependOnMode() throws {
        let apps = loaded(mode: .apps)
        let categories = loaded(mode: .categories)

        XCTAssertEqual(apps.totalReclaimableBytes, categories.totalReclaimableBytes)
        XCTAssertEqual(apps.isTotalSizePartial, categories.isTotalSizePartial)
        XCTAssertEqual(apps.candidateStats, categories.candidateStats)
        XCTAssertEqual(apps.canRequestCleanup, categories.canRequestCleanup)
        for kind in [PendingCleanup.quick, .deep, .selected] {
            let a = try XCTUnwrap(apps.findingsToClean(for: kind)).map(\.path)
            let c = try XCTUnwrap(categories.findingsToClean(for: kind)).map(\.path)
            XCTAssertEqual(Set(a), Set(c), "\(kind)")
        }

        apps.setBrowseMode(.categories)
        XCTAssertEqual(apps.candidateStats, categories.candidateStats)
        XCTAssertEqual(Set(try XCTUnwrap(apps.findingsToClean(for: .selected)).map(\.path)),
                       Set(try XCTUnwrap(categories.findingsToClean(for: .selected)).map(\.path)))
    }

    // MARK: - Group checkbox

    func testOwnerTickSelectsSafeFoldersOnlyAndUntickRemovesThem() throws {
        let vm = loaded()
        let reviewIds = Set(try [chromeStorage, shopModules].map { try folderId($0, in: vm) })
        for group in vm.ownerSections.flatMap(\.groups) where group.isSelectable {
            vm.clearSelection()

            vm.toggleOwnerGroup(group)

            XCTAssertEqual(vm.ownerGroupSelectionState(group), .all, group.owner.key)
            XCTAssertEqual(vm.selection.selectedFolderIds, group.safeFolderIds, group.owner.key)
            XCTAssertTrue(vm.selection.selectedFolderIds.isDisjoint(with: reviewIds), group.owner.key)
            XCTAssertEqual(vm.selectedReviewCount, 0, group.owner.key)

            vm.toggleOwnerGroup(group)

            XCTAssertEqual(vm.ownerGroupSelectionState(group), .none, group.owner.key)
            XCTAssertTrue(vm.selection.selectedFolderIds.isEmpty, group.owner.key)
        }
    }

    func testReviewOnlyGroupIsNotSelectable() throws {
        let vm = loaded()
        let other = try group("other", in: vm)
        vm.clearSelection()

        XCTAssertFalse(other.isSelectable)
        vm.toggleOwnerGroup(other)

        XCTAssertEqual(vm.selectedCandidatesCount, 0)
        XCTAssertEqual(OwnerGroupSection.selectHelp(other), "Review items: tick one by one")
    }

    func testGroupWithHotRowIsPartialAndItsTickNeverSelectsTheHotPath() throws {
        let vm = loaded()
        let npm = try group("tool:npm", in: vm)
        vm.applyCacheActivity(
            [npmA: CacheActivityLabel(activity: .hot, newestEntryDate: Date())], generation: vm.currentScanGeneration
        )

        XCTAssertEqual(vm.ownerGroupSelectionState(npm), .partial)
        XCTAssertFalse(vm.isSelected(path: npmA))

        vm.toggleOwnerGroup(npm)
        XCTAssertFalse(vm.isSelected(path: npmA))
        vm.toggleOwnerGroup(npm)
        XCTAssertFalse(vm.isSelected(path: npmA))
        XCTAssertTrue(vm.isSelected(path: npmB))
        XCTAssertEqual(vm.ownerGroupSelectionState(npm), .partial)
        XCTAssertFalse(try XCTUnwrap(vm.findingsToClean(for: .selected)).map(\.path).contains(npmA))
    }

    // MARK: - Group contents

    func testEveryReclaimableFolderIsInExactlyOneGroup() {
        let vm = loaded()
        let aggregate = FolderRollup.buildAggregate(from: findings)
        let ids = vm.ownerSections.flatMap(\.groups).flatMap(\.folderIds)

        XCTAssertEqual(ids.count, Set(ids).count)
        XCTAssertEqual(Set(ids), Set(aggregate.recordsByFolderId.keys))
    }

    func testHiddenRowsAreCountedSelectedAndTotalled() throws {
        let many = (1...60).map { finding(.projectArtifacts, .safe, Self.home + "/Code/shop/pkg\($0)/dist", Int64($0)) }
        let vm = ScanDashboardViewModel(browseModes: .inMemory())
        vm.applySnapshotResults(ScanReport(findings: many, summaries: []), owners: inputs)
        let shop = try group("project:" + Self.home + "/Code/shop", in: vm)
        vm.clearSelection()

        XCTAssertEqual(shop.rows.count, OwnerGrouping.defaultMaxRowsPerGroup)
        XCTAssertEqual(shop.hiddenRowCount, 10)
        XCTAssertEqual(shop.folderIds.count, 60)
        XCTAssertEqual(shop.totalBytes, (1...60).reduce(Int64(0)) { $0 + Int64($1) })
        XCTAssertEqual(ScanDashboardViewModel.folderBadge(shop.folderIds.count), "60 folders")

        vm.toggleOwnerGroup(shop)
        XCTAssertEqual(vm.selectedCandidatesCount, 60)
        XCTAssertTrue(vm.isSelected(path: Self.home + "/Code/shop/pkg1/dist"))
    }

    func testPartialSizeShowsAsAtLeast() throws {
        let vm = loaded()
        let app = try group("app:com.acme.w", in: vm)

        XCTAssertEqual(app.owner.displayName, "W")
        XCTAssertTrue(app.hasPartialSize)
        XCTAssertTrue(vm.formattedOwnerSize(bytes: app.totalBytes, isPartial: app.hasPartialSize).hasPrefix("≥ "))
    }

    func testExplainOnlyAndAdvancedFindingsAreInNoGroupOrTotal() {
        let vm = loaded()
        let groups = vm.ownerSections.flatMap(\.groups)
        let paths = groups.flatMap(\.rows).map(\.row.folderPath)
        let reclaimable = findings.filter { $0.riskLevel != .advanced }.reduce(Int64(0)) { $0 + $1.sizeBytes }

        XCTAssertFalse(paths.contains { $0.hasPrefix(swap) || $0.hasPrefix(Self.home + "/go") })
        XCTAssertEqual(vm.ownerSections.reduce(Int64(0)) { $0 + $1.totalBytes }, reclaimable)
        XCTAssertEqual(vm.perToolRollups.reduce(Int64(0)) { $0 + $1.totalBytes }, reclaimable)
    }

    func testSectionsFollowTheOwnerOrder() {
        let vm = loaded()

        XCTAssertEqual(vm.ownerSections.map(\.kind), [.app, .project, .tool, .macOS, .other])
        XCTAssertEqual(vm.ownerSections.map { ScanDashboardViewModel.sectionTitle($0.kind) },
                       ["Apps", "Projects", "Developer tools", "macOS", "Other"])
    }

    func testProjectRowsAreLabelledRelativeToTheProject() throws {
        let vm = loaded()
        let shop = try group("project:" + Self.home + "/Code/shop", in: vm)

        XCTAssertEqual(Set(shop.rows.map(\.label)), [".next", "node_modules"])
        XCTAssertEqual(ProjectGroupHeader.meta(root: Self.home + "/Code/shop", activity: nil), Self.home + "/Code/shop")
        XCTAssertEqual(ProjectGroupHeader.meta(root: "/r/shop", activity: "Idle 1 day"), "/r/shop · Idle 1 day")
        XCTAssertNil(vm.projectActivityText(for: shop))
    }

    func testCategoryToolGroupsUseOwnerNames() {
        let vm = loaded(mode: .categories)

        XCTAssertEqual(vm.toolGroups(for: .projectArtifacts).map(\.toolName), ["shop"])
        XCTAssertEqual(vm.toolGroups(for: .browserCaches).map(\.toolName), ["Chrome"])
    }

    // MARK: - Chart

    func testChartTotalMatchesSectionsAndTheOldFeed() {
        let vm = loaded()
        let chart = vm.perToolRollups.reduce(Int64(0)) { $0 + $1.totalBytes }
        let sections = vm.ownerSections.reduce(Int64(0)) { $0 + $1.totalBytes }
        let legacy = FolderRollup.makeToolRollups(from: findings).reduce(Int64(0)) { $0 + $1.totalBytes }

        XCTAssertEqual(chart, sections)
        XCTAssertEqual(chart, legacy)
        XCTAssertEqual(vm.perToolRollups.map(\.share).reduce(0, +), 1, accuracy: 0.0001)
    }

    func testChartUsesOneSlicePerAppAndSharedProjectAndToolSlices() {
        let mb: Int64 = 1_048_576
        let owners: [String: FolderOwner] = [
            "a": FolderOwner(kind: .app, key: "app:chrome", displayName: "Chrome"),
            "b": .project(ProjectRef(root: "/r/shop", name: "shop")),
            "c": .project(ProjectRef(root: "/r/blog", name: "blog")),
            "d": FolderOwner(kind: .tool, key: "tool:npm", displayName: "npm"),
            "e": FolderOwner(kind: .tool, key: "tool:cargo", displayName: "Cargo"),
            "f": .macOS,
            "g": FolderOwner(kind: .app, key: "app:tiny", displayName: "Tiny"),
        ]
        let sizes: [String: Int64] = ["a": 5 * mb, "b": 3 * mb, "c": 2 * mb, "d": 4 * mb, "e": 2 * mb, "f": 2 * mb, "g": 10]
        let records = sizes.mapValues { bytes in
            FolderRecord(id: "", folderPath: "/x", category: .userCaches, bytes: bytes, itemCount: 1, riskLevel: .safe, hasPartialSize: false)
        }

        let rollups = FolderRollup.makeToolRollups(owners: owners, records: records)

        XCTAssertEqual(rollups.map(\.app), ["Developer tools", "Chrome", "Projects", "macOS", "Other"])
        XCTAssertEqual(rollups.last?.totalBytes, 10)
        for label in ["Developer tools", "Projects", "macOS", "Other"] {
            XCTAssertNotEqual(OwnerIcon.symbol(forName: label), "app.fill", label)
        }
    }

    // MARK: - Exclusion

    /// `exclude(path:)` runs this rebuild; called directly so the test never writes the real exclusion list.
    func testExclusionRebuildReplaysResolvedOwners() throws {
        let base = FolderRollup.buildAggregate(from: findings)
        let first = ScanDashboardViewModel.ownerResults(
            aggregate: base, findings: findings,
            resolver: ScanDashboardViewModel.ownerResolver(for: base, inputs: inputs)
        )
        let remaining = findings.filter { $0.path != shopModules }

        let rebuilt = ScanDashboardViewModel.ownerResults(
            aggregate: FolderRollup.buildAggregate(from: remaining), findings: remaining,
            resolver: CachedOwnerResolver(owners: first.ownerByFolderPath)
        )

        let groups = rebuilt.sections.flatMap(\.groups)
        let shop = try XCTUnwrap(groups.first { $0.owner.key == "project:" + Self.home + "/Code/shop" })
        XCTAssertEqual(shop.rows.map(\.row.folderPath), [shopNext])
        XCTAssertTrue(groups.contains { $0.owner.displayName == "W" })
        XCTAssertEqual(
            rebuilt.toolRollups.reduce(Int64(0)) { $0 + $1.totalBytes },
            rebuilt.sections.reduce(Int64(0)) { $0 + $1.totalBytes }
        )
    }

    // MARK: - Persistence

    func testModeDefaultsToAppsAndPersistsAcrossViewModels() throws {
        let suite = "pare.tests.browseMode.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let first = ScanDashboardViewModel(browseModes: BrowseModeStore(defaults: defaults))
        XCTAssertEqual(first.browseMode, .apps)

        first.setBrowseMode(.categories)

        XCTAssertEqual(defaults.string(forKey: BrowseModeStore.storageKey), "categories")
        XCTAssertEqual(ScanDashboardViewModel(browseModes: BrowseModeStore(defaults: defaults)).browseMode, .categories)
        XCTAssertEqual(BrowseModeStore.storageKey, "pare.smartScan.browseMode")
    }

    func testInMemoryStoreNeverWritesDefaults() {
        let stored = UserDefaults.standard.string(forKey: BrowseModeStore.storageKey)
        let store = BrowseModeStore.inMemory()
        XCTAssertEqual(store.mode, .apps)

        store.mode = store.mode == .apps ? .categories : .apps

        XCTAssertEqual(store.mode, .categories)
        XCTAssertEqual(UserDefaults.standard.string(forKey: BrowseModeStore.storageKey), stored)
    }

    func testUnknownStoredModeFallsBackToApps() throws {
        let suite = "pare.tests.browseMode.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("tree", forKey: BrowseModeStore.storageKey)

        XCTAssertEqual(BrowseModeStore(defaults: defaults).mode, .apps)
    }

    // MARK: - Installed-app wait

    func testInstalledAppsWaitGivesUpAtItsLimit() async {
        let box = TimeBoxedValue<InstalledAppIndex>()
        let started = Date()

        let value = await box.value(waitingAtMost: 0.05)

        XCTAssertNil(value)
        XCTAssertLessThan(Date().timeIntervalSince(started), 1)
    }

    func testInstalledAppsWaitReturnsAValueThatArrives() async {
        let box = TimeBoxedValue<Int>()
        Task.detached { box.fulfill(7) }

        let value = await box.value(waitingAtMost: 5)

        XCTAssertEqual(value, 7)
    }

    func testInstalledAppsAlreadyLoadedAreReturnedAtOnce() async {
        let box = TimeBoxedValue<Int>()
        box.fulfill(3)

        let value = await box.value(waitingAtMost: 0)

        XCTAssertEqual(value, 3)
    }

    // MARK: - Copy and symbols

    func testChipsAndOwnerSymbolsResolve() {
        XCTAssertEqual(CategoryStyle.chipLabel(for: .developerBuildArtifacts), "Build")
        XCTAssertEqual(CategoryStyle.chipLabel(for: .launchAgents), "Agent")
        let owners: [FolderOwner] = [
            .macOS, .other, .project(ProjectRef(root: "/r/a", name: "a")),
            FolderOwner(kind: .tool, key: "tool:homebrew", displayName: "Homebrew"),
            FolderOwner(kind: .tool, key: "tool:new", displayName: "NewTool"),
        ]
        for name in owners.map(OwnerIcon.symbol(for:)) + ["Projects", "Developer tools"].map(OwnerIcon.symbol(forName:)) {
            XCTAssertNotNil(NSImage(systemSymbolName: name, accessibilityDescription: nil), name)
        }
        XCTAssertEqual(OwnerGroupSection.ownerHelp(.macOS), "Owned by macOS")
        XCTAssertEqual(OwnerGroupSection.ownerHelp(.other), "Owner unknown")
        XCTAssertEqual(BrowseModeSwitch.title(.apps), "Apps")
        XCTAssertEqual(BrowseModeSwitch.title(.categories), "Categories")
    }

    // MARK: - Helpers

    private func finding(
        _ category: ScanCategory, _ risk: RiskLevel, _ path: String, _ bytes: Int64, complete: Bool = true
    ) -> ScanFinding {
        ScanFinding(
            category: category, riskLevel: risk, reason: "test", path: path, sizeBytes: bytes,
            lastUsed: nil, confidence: 1, isSizeComplete: complete
        )
    }
}
