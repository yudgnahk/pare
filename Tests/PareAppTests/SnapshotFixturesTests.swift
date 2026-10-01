import XCTest
import PareCore
@testable import PareApp

/// Snapshot fixtures must never name a real file, so no stray interaction can clean or restore one.
@MainActor
final class SnapshotFixturesTests: XCTestCase {

    private let fakeRoot = SnapshotFixtures.root + "/"

    func testScanFindingsLiveUnderTheFakeRoot() {
        let paths = SnapshotFixtures.scanReport.findings.map(\.path)

        XCTAssertFalse(paths.isEmpty)
        for path in paths {
            XCTAssertTrue(path.hasPrefix(fakeRoot), path)
        }
    }

    func testHistoryOriginalAndTrashedPathsLiveUnderTheFakeRoot() {
        let items = SnapshotFixtures.historyTransactions().flatMap(\.items)

        XCTAssertFalse(items.isEmpty)
        for item in items {
            XCTAssertTrue(item.originalPath.hasPrefix(fakeRoot), item.originalPath)
            XCTAssertTrue(item.trashedPath?.hasPrefix(fakeRoot) == true, item.trashedPath ?? "nil")
        }
    }

    func testFakeRootDoesNotExist() {
        XCTAssertFalse(FileManager.default.fileExists(atPath: SnapshotFixtures.root))
    }

    func testSnapshotStoreSharesOneInjectedCoordinator() {
        let store = SnapshotFixtures.makeModelStore()

        XCTAssertTrue(store.scan.cleanup === store.cleanup)
        XCTAssertTrue(store.disk.coordinator === store.cleanup)
    }
}
