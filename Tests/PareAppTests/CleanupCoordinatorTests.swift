import XCTest
import PareCore
@testable import PareApp

@MainActor
final class CleanupCoordinatorTests: XCTestCase {

    private var storeDir: URL!
    private var tempFile: URL!
    private var fixtureDirectory: URL!

    override func setUp() async throws {
        storeDir = FileManager.default.temporaryDirectory
            .appending(path: "CleanupCoordinatorTests-\(UUID().uuidString)")
        fixtureDirectory = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Caches/Pare-CleanupCoordinatorTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: fixtureDirectory, withIntermediateDirectories: true)
        tempFile = fixtureDirectory.appending(path: "fixture.bin")
        try Data("test".utf8).write(to: tempFile)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: storeDir)
        try? FileManager.default.removeItem(at: tempFile)
        try? FileManager.default.removeItem(at: fixtureDirectory)
    }

    /// The injected engine (backed by a temp store) must be the one actually used,
    /// not the default `CleanupEngine()` writing to the shared app-support store.
    func testConfirmUsesInjectedEngine() async {
        let store = CleanupTransactionStore(directory: storeDir)
        let engine = CleanupEngine(store: store, exclusionsProvider: { .empty }, now: { .distantFuture })
        let coordinator = CleanupCoordinator(engine: engine)
        let finding = ScanFinding(
            category: .userCaches,
            riskLevel: .safe,
            reason: "Test",
            path: tempFile.path,
            sizeBytes: 4,
            lastUsed: Date(),
            confidence: 1.0
        )

        coordinator.confirm(.quick, findings: [finding])

        for _ in 0..<50 where coordinator.isCleaning {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }

        XCTAssertEqual(coordinator.state, .done(bytesFreed: 4, skippedCount: 0))
        XCTAssertFalse((try? store.loadAll())?.isEmpty ?? true)
    }
}
