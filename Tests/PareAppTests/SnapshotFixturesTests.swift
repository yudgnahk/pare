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

    func testOwnerInputsNameOnlyFakePaths() {
        let inputs = SnapshotFixtures.ownerInputs
        let probe = inputs.probe as? SnapshotFixtures.FixtureProjectProbe
        let paths = [inputs.homeDirectory.path] + inputs.registeredRoots.map(\.path)
            + Array(probe?.gitRoots ?? []) + Array(probe?.markerRoots ?? [])

        XCTAssertNotNil(probe)
        XCTAssertEqual(paths.count, 4)
        for path in paths {
            XCTAssertTrue(path.hasPrefix(fakeRoot), path)
        }
    }

    func testFixtureFindingsNeverNestUnderAnotherFinding() {
        let paths = SnapshotFixtures.scanReport.findings.map(\.path)
        for path in paths {
            XCTAssertFalse(paths.contains { path.hasPrefix($0 + "/") }, path)
        }
    }

    func testByAppSceneShowsEveryOwnerKind() {
        let vm = ScanDashboardViewModel(browseModes: .inMemory())
        vm.applySnapshotResults(SnapshotFixtures.scanReport, owners: SnapshotFixtures.ownerInputs)
        let names = Set(vm.ownerSections.flatMap(\.groups).map(\.owner.displayName))

        XCTAssertEqual(vm.ownerSections.map(\.kind), [.app, .project, .tool, .macOS, .other])
        XCTAssertTrue(names.isSuperset(of: ["Whisper", "VS Code", "shop", "blog", "npm"]), "\(names)")
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
