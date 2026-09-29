import XCTest
@testable import PareApp

@MainActor
final class ScanDashboardViewModelTests: XCTestCase {

    /// Other view models (Disk Analyzer) read scan findings through this snapshot;
    /// it must start empty rather than crash before any scan has run.
    func testLatestFindingsSnapshotStartsEmpty() {
        let vm = ScanDashboardViewModel()
        XCTAssertTrue(vm.latestFindingsSnapshot.isEmpty)
    }

    func testInjectedCleanupCoordinatorIsUsed() {
        let coordinator = CleanupCoordinator()
        let vm = ScanDashboardViewModel(cleanup: coordinator)
        XCTAssertTrue(vm.cleanup === coordinator)
    }

    /// One coordinator means one busy guard across Smart Scan and the Disk Analyzer.
    func testAppModelStoreSharesOneCleanupCoordinator() {
        let store = AppModelStore()
        XCTAssertTrue(store.scan.cleanup === store.cleanup)
        XCTAssertTrue(store.disk.coordinator === store.cleanup)
    }
}
