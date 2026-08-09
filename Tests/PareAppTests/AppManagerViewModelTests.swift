import XCTest
import PareCore
@testable import PareApp

@MainActor
final class AppManagerViewModelTests: XCTestCase {

    // MARK: - Fixtures

    private func makeApp(
        name: String,
        bundleID: String? = nil,
        sizeBytes: Int64 = 0,
        installDate: Date? = nil,
        lastUsed: Date? = nil,
        isSystemApp: Bool = false,
        updateInfo: UpdateInfo? = nil
    ) -> InstalledApp {
        InstalledApp(
            name: name,
            bundleID: bundleID ?? "com.test.\(name.lowercased())",
            version: "1.0",
            buildVersion: "100",
            path: "/Applications/\(name).app",
            sizeBytes: sizeBytes,
            installDate: installDate,
            lastUsed: lastUsed,
            isMAS: false,
            isSystemApp: isSystemApp,
            updateInfo: updateInfo
        )
    }

    private func makeUpdate(bundleID: String, installed: String = "1.0", available: String = "2.0") -> UpdateInfo {
        UpdateInfo(
            bundleID: bundleID,
            installedVersion: installed,
            availableVersion: available,
            channel: .sparkle
        )
    }

    // MARK: - LoadState / UninstallState equality

    func testLoadStateEquality() {
        XCTAssertEqual(LoadState.idle, .idle)
        XCTAssertEqual(LoadState.loading, .loading)
        XCTAssertEqual(LoadState.loaded, .loaded)
        XCTAssertEqual(LoadState.error("x"), .error("x"))
        XCTAssertNotEqual(LoadState.error("x"), .error("y"))
        XCTAssertNotEqual(LoadState.idle, .loading)
        XCTAssertNotEqual(LoadState.loaded, .error("x"))
    }

    func testUninstallStateEquality() {
        XCTAssertEqual(AppManagerViewModel.UninstallState.idle, .idle)
        XCTAssertEqual(
            AppManagerViewModel.UninstallState.done(trashed: 2, failed: 1),
            .done(trashed: 2, failed: 1)
        )
        XCTAssertNotEqual(
            AppManagerViewModel.UninstallState.done(trashed: 2, failed: 1),
            .done(trashed: 2, failed: 0)
        )
        XCTAssertNotEqual(AppManagerViewModel.UninstallState.confirming, .uninstalling)
    }

    // MARK: - Filtering

    func testFilteredAppsHidesSystemAppsWhenToggled() {
        let vm = AppManagerViewModel()
        vm.apps = [
            makeApp(name: "Finder", isSystemApp: true),
            makeApp(name: "UserApp"),
        ]

        XCTAssertEqual(vm.filteredApps.count, 2)
        vm.hideSystemApps = true
        XCTAssertEqual(vm.filteredApps.map(\.name), ["UserApp"])
    }

    func testFilteredAppsShowsOnlyOutdatedWhenToggled() {
        let vm = AppManagerViewModel()
        let outdated = makeApp(name: "OldApp", bundleID: "com.test.old",
                               updateInfo: makeUpdate(bundleID: "com.test.old"))
        let current = makeApp(name: "FreshApp", bundleID: "com.test.fresh",
                              updateInfo: makeUpdate(bundleID: "com.test.fresh", installed: "2.0", available: "2.0"))
        vm.apps = [outdated, current, makeApp(name: "NoInfo")]

        vm.showOnlyOutdated = true
        XCTAssertEqual(vm.filteredApps.map(\.name), ["OldApp"])
    }

    func testFilteredAppsSearchMatchesNameAndBundleID() {
        let vm = AppManagerViewModel()
        vm.apps = [
            makeApp(name: "Alpha", bundleID: "com.vendor.alpha"),
            makeApp(name: "Beta", bundleID: "com.vendor.beta"),
        ]

        vm.searchText = "alph"
        XCTAssertEqual(vm.filteredApps.map(\.name), ["Alpha"])

        vm.searchText = "vendor.beta"
        XCTAssertEqual(vm.filteredApps.map(\.name), ["Beta"])

        vm.searchText = "zzz"
        XCTAssertTrue(vm.filteredApps.isEmpty)
    }

    // MARK: - Sorting

    func testDefaultSortIsSizeDescending() {
        let vm = AppManagerViewModel()
        vm.apps = [
            makeApp(name: "Small", sizeBytes: 10),
            makeApp(name: "Big", sizeBytes: 1_000),
            makeApp(name: "Medium", sizeBytes: 100),
        ]

        XCTAssertEqual(vm.sortField, .size)
        XCTAssertFalse(vm.sortAscending)
        XCTAssertEqual(vm.filteredApps.map(\.name), ["Big", "Medium", "Small"])
    }

    func testToggleSortFlipsDirectionOnSameFieldAndResetsOnNewField() {
        let vm = AppManagerViewModel()
        vm.apps = [
            makeApp(name: "Small", sizeBytes: 10),
            makeApp(name: "Big", sizeBytes: 1_000),
        ]

        vm.toggleSort(.size)
        XCTAssertTrue(vm.sortAscending)
        XCTAssertEqual(vm.filteredApps.map(\.name), ["Small", "Big"])

        // Switching to name resets to ascending for name.
        vm.toggleSort(.name)
        XCTAssertEqual(vm.sortField, .name)
        XCTAssertTrue(vm.sortAscending)
        XCTAssertEqual(vm.filteredApps.map(\.name), ["Big", "Small"])
    }

    // MARK: - Aggregates

    func testAggregateCounters() {
        let vm = AppManagerViewModel()
        vm.apps = [
            makeApp(name: "A", bundleID: "com.t.a", sizeBytes: 100,
                    updateInfo: makeUpdate(bundleID: "com.t.a")),
            makeApp(name: "B", bundleID: "com.t.b", sizeBytes: 200),
            makeApp(name: "Sys", bundleID: "com.apple.sys", sizeBytes: 300, isSystemApp: true),
        ]

        XCTAssertEqual(vm.totalSizeBytes, 600)
        XCTAssertEqual(vm.outdatedCount, 1)
        // System apps are excluded from update checks.
        XCTAssertEqual(vm.updateCheckCount, 2)
    }

    // MARK: - Uninstall flow state machine

    func testCancelUninstallResetsFlowState() {
        let vm = AppManagerViewModel()
        vm.selectedApp = makeApp(name: "Doomed")
        vm.pendingLeftovers = []
        vm.uninstallState = .confirming
        vm.showUninstallSheet = true

        vm.cancelUninstall()

        XCTAssertEqual(vm.uninstallState, .idle)
        XCTAssertFalse(vm.showUninstallSheet)
        XCTAssertNil(vm.selectedApp)
        XCTAssertTrue(vm.pendingLeftovers.isEmpty)
    }

    // MARK: - Feedback

    func testDismissUpdateFeedbackClearsMessage() {
        let vm = AppManagerViewModel()
        vm.updateFeedback = "Updated something"
        vm.dismissUpdateFeedback()
        XCTAssertNil(vm.updateFeedback)
    }

    func testCancelLoadReturnsToIdle() {
        let vm = AppManagerViewModel()
        vm.loadState = .loading
        vm.cancelLoad()
        XCTAssertEqual(vm.loadState, .idle)
    }
}
