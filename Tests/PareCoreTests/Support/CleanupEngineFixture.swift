import Foundation
@testable import PareCore

/// Builds a `CleanupEngine` whose in-use gate never spawns `lsof` or reads `NSWorkspace`:
/// by default nothing is open and nothing is running. Other parameters keep the production defaults.
enum CleanupEngineFixture {
    static func make(
        store: CleanupTransactionStore,
        projectRootsProvider: (@Sendable () async -> [String])? = nil,
        exclusionsProvider: (@Sendable () -> ExclusionList)? = nil,
        now: @escaping @Sendable () -> Date = { Date() },
        trashItem: (@Sendable (URL) throws -> URL?)? = nil,
        openFiles: any OpenFileSnapshotProviding = CountingSnapshotProvider(snapshot: .nothingOpen),
        runningApps: any RunningAppsProviding = FixedRunningAppsList(apps: [])
    ) -> CleanupEngine {
        CleanupEngine(
            store: store,
            projectRootsProvider: projectRootsProvider,
            exclusionsProvider: exclusionsProvider,
            now: now,
            trashItem: trashItem,
            openFiles: openFiles,
            runningApps: runningApps
        )
    }
}

extension OpenFileSnapshot {
    /// A successful snapshot with no open files, unlike `nil`, which means the check was unavailable.
    static let nothingOpen = OpenFileSnapshot(lsofFieldOutput: "")
}

final class CountingSnapshotProvider: OpenFileSnapshotProviding, @unchecked Sendable {
    private let snapshotValue: OpenFileSnapshot?
    private let lock = NSLock()
    private var count = 0

    init(snapshot: OpenFileSnapshot?) {
        snapshotValue = snapshot
    }

    var calls: Int { lock.withLock { count } }

    func snapshot() async -> OpenFileSnapshot? {
        lock.withLock { count += 1 }
        return snapshotValue
    }
}

struct FixedRunningAppsList: RunningAppsProviding {
    let apps: [RunningApp]

    func runningApps() -> [RunningApp] { apps }
}
