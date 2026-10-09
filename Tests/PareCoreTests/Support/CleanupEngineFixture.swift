import Foundation
@testable import PareCore

/// Builds a `CleanupEngine` whose in-use gate never spawns `lsof` or reads `NSWorkspace`: by default
/// nothing is open, nothing is running and free space is unknown. Others keep production defaults.
enum CleanupEngineFixture {
    static func make(
        store: CleanupTransactionStore,
        projectRootsProvider: (@Sendable () async -> [String])? = nil,
        exclusionsProvider: (@Sendable () -> ExclusionList)? = nil,
        now: @escaping @Sendable () -> Date = { Date() },
        trashItem: (@Sendable (URL) throws -> URL?)? = nil,
        gitInspector: any GitArtifactInspecting = SystemGitArtifactInspector(),
        openFiles: any OpenFileSnapshotProviding = CountingSnapshotProvider(snapshot: .nothingOpen),
        runningApps: any RunningAppsProviding = FixedRunningAppsList(apps: []),
        freeSpace: any VolumeFreeSpaceProviding = FixedFreeSpace(reading: nil)
    ) -> CleanupEngine {
        CleanupEngine(
            store: store,
            projectRootsProvider: projectRootsProvider,
            exclusionsProvider: exclusionsProvider,
            now: now,
            trashItem: trashItem,
            gitInspector: gitInspector,
            openFiles: openFiles,
            runningApps: runningApps,
            freeSpace: freeSpace
        )
    }
}

extension OpenFileSnapshot {
    /// A listing that holds nothing relevant; empty output is never returned by the real provider (it yields nil).
    static let nothingOpenListing = "p1\ncfixture\nn/nonexistent/pare-fixture\n"
    static let nothingOpen = OpenFileSnapshot(lsofFieldOutput: nothingOpenListing)
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

/// One canned reading for every volume; nil is an unreadable volume.
struct FixedFreeSpace: VolumeFreeSpaceProviding {
    let reading: VolumeFreeSpace?

    func freeSpace(forVolumeContaining url: URL) -> VolumeFreeSpace? { reading }

    /// A 245 GB volume whose free space lands in `tier`.
    static func tier(_ tier: DiskPressureTier) -> FixedFreeSpace {
        let gb: Int64 = 1_000_000_000
        let free: Int64 = switch tier {
        case .comfortable: 100 * gb
        case .low: 30 * gb
        case .critical: 5 * gb
        }
        return FixedFreeSpace(reading: VolumeFreeSpace(importantUsageBytes: free, availableBytes: free, totalBytes: 245 * gb))
    }
}
