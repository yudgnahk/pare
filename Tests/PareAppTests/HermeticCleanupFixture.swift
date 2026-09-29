import Combine
import XCTest
import PareCore
@testable import PareApp

/// Temp-only cleanup sandbox: fixtures, undo store and "Trash" all live under one `/private/tmp` root.
struct HermeticCleanupFixture {
    let root: URL
    /// Contains `/Library/Caches/` so `ScanPolicy.isLowImpactPath` accepts it, like `CleanupEngineTests`.
    let cacheDirectory: URL
    let trashDirectory: URL
    let store: CleanupTransactionStore

    init(name: String) throws {
        root = URL(fileURLWithPath: "/private/tmp/\(name)-\(UUID().uuidString)")
        cacheDirectory = root.appending(path: "Library/Caches/com.pare.test")
        trashDirectory = root.appending(path: "Trash")
        store = CleanupTransactionStore(directory: root.appending(path: "transactions"))
        try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: trashDirectory, withIntermediateDirectories: true)
    }

    func makeFile(named name: String, contents: String = "test") throws -> URL {
        let url = cacheDirectory.appending(path: name)
        try Data(contents.utf8).write(to: url)
        return url
    }

    func makeEngine() -> CleanupEngine {
        let trash = trashDirectory
        return CleanupEngine(
            store: store,
            projectRootsProvider: { [] },
            exclusionsProvider: { .empty },
            now: { .distantFuture },
            trashItem: { url in
                let destination = trash.appending(path: "\(UUID().uuidString)-\(url.lastPathComponent)")
                try FileManager.default.moveItem(at: url, to: destination)
                return destination
            }
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}

extension XCTestCase {
    /// Waits for the coordinator to leave `.cleaning` for a terminal state instead of sleeping.
    @MainActor
    func waitForCleanupToFinish(_ coordinator: CleanupCoordinator, timeout: TimeInterval = 10) async {
        let finished = expectation(description: "cleanup finished")
        let subscription = coordinator.$state
            .first { state in
                switch state {
                case .done, .error: return true
                default: return false
                }
            }
            .sink { _ in finished.fulfill() }
        await fulfillment(of: [finished], timeout: timeout)
        subscription.cancel()
    }
}
