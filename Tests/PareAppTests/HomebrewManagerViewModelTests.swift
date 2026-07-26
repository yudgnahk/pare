import XCTest
import PareCore
@testable import PareApp

@MainActor
final class HomebrewManagerViewModelTests: XCTestCase {

    // MARK: - Fixtures

    private func makeFormula(
        name: String,
        desc: String = "",
        sizeBytes: Int64 = 0,
        installDate: Date? = nil
    ) -> BrewFormula {
        BrewFormula(
            name: name,
            desc: desc,
            version: "1.0",
            installedOnRequest: true,
            pinned: false,
            installDate: installDate,
            dependencies: [],
            sizeBytes: sizeBytes
        )
    }

    private func makeCask(token: String, apps: [String] = [], isOrphaned: Bool = false) -> BrewCask {
        BrewCask(
            token: token,
            version: "1.0",
            autoUpdates: false,
            installedAppNames: apps,
            installDate: nil,
            isOrphaned: isOrphaned
        )
    }

    private func makeOutdated(
        name: String,
        pinned: Bool = false,
        isAutoUpdate: Bool = false,
        isFormula: Bool = true
    ) -> BrewOutdatedPackage {
        BrewOutdatedPackage(
            name: name,
            installedVersions: ["1.0"],
            currentVersion: "2.0",
            pinned: pinned,
            isAutoUpdate: isAutoUpdate,
            isFormula: isFormula
        )
    }

    private func makeCandidate(token: String, appName: String) -> MigrationCandidate {
        MigrationCandidate(caskToken: token, appName: appName, bundleID: nil, currentPath: "/Applications/\(appName).app")
    }

    // MARK: - LoadState

    func testLoadStateEquality() {
        XCTAssertEqual(LoadState.idle, .idle)
        XCTAssertEqual(LoadState.error("a"), .error("a"))
        XCTAssertNotEqual(LoadState.error("a"), .error("b"))
        XCTAssertNotEqual(LoadState.loading, .loaded)
    }

    // MARK: - Outdated partition

    func testBrewManagedVersusAutoUpdatePartition() {
        let vm = HomebrewManagerViewModel()
        let formula = makeOutdated(name: "wget")
        let managedCask = makeOutdated(name: "firefox", isAutoUpdate: false, isFormula: false)
        let autoCask = makeOutdated(name: "chrome", isAutoUpdate: true, isFormula: false)
        let autoFormulaLike = makeOutdated(name: "weird", isAutoUpdate: true, isFormula: true)
        vm.outdated = [formula, managedCask, autoCask, autoFormulaLike]

        XCTAssertEqual(vm.brewManagedOutdated.map(\.name), ["wget", "firefox", "weird"])
        XCTAssertEqual(vm.autoUpdateOutdated.map(\.name), ["chrome"])
    }

    // MARK: - Filtering & sorting

    func testFilteredFormulaeMatchesNameOrDescription() {
        let vm = HomebrewManagerViewModel()
        vm.formulae = [
            makeFormula(name: "wget", desc: "internet file retriever"),
            makeFormula(name: "jq", desc: "JSON processor"),
        ]

        vm.searchText = "json"
        XCTAssertEqual(vm.filteredFormulae.map(\.name), ["jq"])

        vm.searchText = "wge"
        XCTAssertEqual(vm.filteredFormulae.map(\.name), ["wget"])
    }

    func testFormulaDefaultSortIsSizeDescendingAndToggleFlips() {
        let vm = HomebrewManagerViewModel()
        vm.formulae = [
            makeFormula(name: "small", sizeBytes: 5),
            makeFormula(name: "big", sizeBytes: 500),
        ]

        XCTAssertEqual(vm.formulaSortField, .size)
        XCTAssertFalse(vm.formulaSortAscending)
        XCTAssertEqual(vm.filteredFormulae.map(\.name), ["big", "small"])

        vm.toggleFormulaSort(.size)
        XCTAssertTrue(vm.formulaSortAscending)
        XCTAssertEqual(vm.filteredFormulae.map(\.name), ["small", "big"])

        vm.toggleFormulaSort(.name)
        XCTAssertEqual(vm.formulaSortField, .name)
        XCTAssertTrue(vm.formulaSortAscending)
        XCTAssertEqual(vm.filteredFormulae.map(\.name), ["big", "small"])
    }

    func testFilteredCasksFloatsOrphansToTop() {
        let vm = HomebrewManagerViewModel()
        vm.casks = [
            makeCask(token: "alfred"),
            makeCask(token: "zoom", isOrphaned: true),
            makeCask(token: "beta-app"),
        ]

        XCTAssertEqual(vm.filteredCasks.map(\.token), ["zoom", "alfred", "beta-app"])
        XCTAssertEqual(vm.orphanedCasksCount, 1)
    }

    func testFilteredCasksSearchMatchesTokenAndAppNames() {
        let vm = HomebrewManagerViewModel()
        vm.casks = [
            makeCask(token: "visual-studio-code", apps: ["Visual Studio Code.app"]),
            makeCask(token: "iterm2", apps: ["iTerm.app"]),
        ]

        vm.searchText = "iterm"
        XCTAssertEqual(vm.filteredCasks.map(\.token), ["iterm2"])

        vm.searchText = "studio"
        XCTAssertEqual(vm.filteredCasks.map(\.token), ["visual-studio-code"])
    }

    func testFilteredOutdatedAndMigrationCandidatesRespectSearch() {
        let vm = HomebrewManagerViewModel()
        vm.outdated = [makeOutdated(name: "wget"), makeOutdated(name: "jq")]
        vm.migrationCandidates = [
            makeCandidate(token: "figma", appName: "Figma"),
            makeCandidate(token: "slack", appName: "Slack"),
        ]

        vm.searchText = "wg"
        XCTAssertEqual(vm.filteredOutdated.map(\.name), ["wget"])

        vm.searchText = "sla"
        XCTAssertEqual(vm.filteredMigrationCandidates.map(\.caskToken), ["slack"])
    }

    // MARK: - Selection

    func testToggleSelectionIsScopedToActiveTab() {
        let vm = HomebrewManagerViewModel()
        vm.formulae = [makeFormula(name: "wget")]
        vm.casks = [makeCask(token: "zoom")]

        vm.selectedTab = .formulae
        vm.toggleSelection(id: "wget")
        XCTAssertTrue(vm.isSelected("wget"))
        XCTAssertEqual(vm.selectedCount, 1)

        vm.selectedTab = .casks
        XCTAssertFalse(vm.isSelected("wget"), "Selection must not leak across tabs")
        XCTAssertEqual(vm.selectedCount, 0)

        vm.toggleSelection(id: "zoom")
        XCTAssertEqual(vm.selectedCount, 1)

        // Toggling again deselects.
        vm.toggleSelection(id: "zoom")
        XCTAssertEqual(vm.selectedCount, 0)
    }

    func testPinnedOutdatedPackagesCannotBeSelected() {
        let vm = HomebrewManagerViewModel()
        vm.outdated = [makeOutdated(name: "pinned-pkg", pinned: true), makeOutdated(name: "free-pkg")]
        vm.selectedTab = .outdated

        vm.toggleSelection(id: "pinned-pkg")
        XCTAssertFalse(vm.isSelected("pinned-pkg"))
        XCTAssertEqual(vm.selectedCount, 0)

        vm.toggleSelection(id: "free-pkg")
        XCTAssertTrue(vm.isSelected("free-pkg"))
    }

    func testSelectAllVisibleOnOutdatedSkipsPinnedAndActionableCountAgrees() {
        let vm = HomebrewManagerViewModel()
        vm.outdated = [
            makeOutdated(name: "a"),
            makeOutdated(name: "b", pinned: true),
            makeOutdated(name: "c"),
        ]
        vm.selectedTab = .outdated

        vm.selectAllVisible()
        XCTAssertEqual(vm.selectedCount, 2)
        XCTAssertEqual(vm.actionableSelectedCount, 2)
        XCTAssertFalse(vm.isSelected("b"))

        vm.clearSelection()
        XCTAssertEqual(vm.selectedCount, 0)
    }

    func testSelectAllVisibleHonorsSearchFilter() {
        let vm = HomebrewManagerViewModel()
        vm.formulae = [makeFormula(name: "wget"), makeFormula(name: "jq")]
        vm.selectedTab = .formulae
        vm.searchText = "wget"

        vm.selectAllVisible()

        XCTAssertTrue(vm.isSelected("wget"))
        XCTAssertFalse(vm.isSelected("jq"))
        XCTAssertEqual(vm.selectedCount, 1)
    }

    // MARK: - Confirmation flow

    func testRequestBulkActionBuildsPerItemConfirmation() {
        let vm = HomebrewManagerViewModel()
        vm.formulae = [makeFormula(name: "wget"), makeFormula(name: "jq")]
        vm.selectedTab = .formulae
        vm.selectAllVisible()

        vm.requestBulkAction()

        let pending = vm.pendingConfirmation
        XCTAssertNotNil(pending)
        XCTAssertEqual(pending?.action, .uninstallFormulae)
        XCTAssertEqual(Set(pending?.names ?? []), ["wget", "jq"])
        XCTAssertEqual(pending?.commands.count, 2)
        XCTAssertTrue(pending?.commands.allSatisfy { $0.contains("uninstall") } ?? false)

        vm.cancelConfirmation()
        XCTAssertNil(vm.pendingConfirmation)
    }

    func testRequestUpgradeAllUsesAggregateNonGreedyCommand() {
        let vm = HomebrewManagerViewModel()
        vm.outdated = [
            makeOutdated(name: "wget"),
            makeOutdated(name: "auto-cask", isAutoUpdate: true, isFormula: false),
        ]

        vm.requestUpgradeAll()

        let pending = vm.pendingConfirmation
        XCTAssertNotNil(pending)
        XCTAssertEqual(pending?.action, .upgradePackages)
        // Non-greedy: only brew-managed packages; single aggregate `upgrade` command.
        XCTAssertEqual(pending?.names, ["wget"])
        XCTAssertEqual(pending?.commands, [["upgrade"]])
        XCTAssertEqual(pending?.warnsAboutAutoUpdates, false)
    }

    func testRequestGreedyUpgradeAllWarnsAboutAutoUpdaters() {
        let vm = HomebrewManagerViewModel()
        vm.outdated = [
            makeOutdated(name: "wget"),
            makeOutdated(name: "auto-cask", isAutoUpdate: true, isFormula: false),
        ]

        vm.requestGreedyUpgradeAll()

        let pending = vm.pendingConfirmation
        XCTAssertEqual(pending?.commands, [["upgrade", "--greedy"]])
        XCTAssertEqual(Set(pending?.names ?? []), ["wget", "auto-cask"])
        XCTAssertEqual(pending?.warnsAboutAutoUpdates, true)
    }

    func testRequestUpgradeAllWithNothingOutdatedDoesNothing() {
        let vm = HomebrewManagerViewModel()
        vm.outdated = []
        vm.requestUpgradeAll()
        XCTAssertNil(vm.pendingConfirmation)
    }

    func testUpgradeSinglePinnedPackageIsRefused() {
        let vm = HomebrewManagerViewModel()
        vm.upgrade(package: makeOutdated(name: "pinned", pinned: true))
        XCTAssertNil(vm.pendingConfirmation)

        vm.upgrade(package: makeOutdated(name: "free"))
        XCTAssertNotNil(vm.pendingConfirmation)
        XCTAssertEqual(vm.pendingConfirmation?.names, ["free"])
    }

    // MARK: - Leave Homebrew flow

    func testLeaveHomebrewRequestAndCancelResetState() {
        let vm = HomebrewManagerViewModel()
        let cask = makeCask(token: "zoom")

        vm.requestLeaveHomebrew(cask: cask)
        XCTAssertEqual(vm.leaveConfirmCask?.token, "zoom")
        XCTAssertFalse(vm.leaveForceQuit)

        vm.leaveForceQuit = true
        vm.cancelLeaveHomebrew()
        XCTAssertNil(vm.leaveConfirmCask)
        XCTAssertFalse(vm.leaveForceQuit)
    }
}
