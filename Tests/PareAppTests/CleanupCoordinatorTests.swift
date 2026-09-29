import XCTest
import PareCore
@testable import PareApp

@MainActor
final class CleanupCoordinatorTests: XCTestCase {

    private var fixture: HermeticCleanupFixture!

    override func setUp() async throws {
        fixture = try HermeticCleanupFixture(name: "CleanupCoordinatorTests")
    }

    override func tearDown() async throws {
        fixture.remove()
    }

    private func makeFinding(path: String, sizeBytes: Int64 = 4) -> ScanFinding {
        ScanFinding(
            category: .userCaches,
            riskLevel: .safe,
            reason: "Test",
            path: path,
            sizeBytes: sizeBytes,
            lastUsed: Date(),
            confidence: 1.0
        )
    }

    /// The injected engine (backed by a temp store) must be the one actually used,
    /// not the default `CleanupEngine()` writing to the shared app-support store.
    func testConfirmUsesInjectedEngine() async throws {
        let file = try fixture.makeFile(named: "fixture.bin")
        let coordinator = CleanupCoordinator(engine: fixture.makeEngine())

        coordinator.confirm(.quick, findings: [makeFinding(path: file.path)])
        await waitForCleanupToFinish(coordinator)

        XCTAssertEqual(coordinator.state, .done(bytesFreed: 4, skippedCount: 0))
        XCTAssertFalse((try? fixture.store.loadAll())?.isEmpty ?? true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        let trashed = try FileManager.default.contentsOfDirectory(atPath: fixture.trashDirectory.path)
        XCTAssertEqual(trashed.count, 1, "the item must land in the fixture's trash, not the real Trash")
    }
}
