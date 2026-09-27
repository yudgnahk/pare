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
}
