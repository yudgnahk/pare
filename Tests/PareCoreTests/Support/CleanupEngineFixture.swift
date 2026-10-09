import Foundation
@testable import PareCore

/// Builds a `CleanupEngine` that never spawns git, go, ps, pnpm or lsof, or reads `NSWorkspace`: by default
/// nothing is open or running, nothing is in a git repository, Codex is idle, no pnpm store or Go cache
/// override exists, and free space is unknown.
enum CleanupEngineFixture {
    static func make(
        store: CleanupTransactionStore,
        projectRootsProvider: (@Sendable () async -> [String])? = nil,
        exclusionsProvider: (@Sendable () -> ExclusionList)? = nil,
        now: @escaping @Sendable () -> Date = { Date() },
        trashItem: (@Sendable (URL) throws -> URL?)? = nil,
        gitInspector: any GitArtifactInspecting = StubGitInspector(status: .notInRepository),
        goCacheLocations: GoCacheLocations = GoCacheLocations(query: { nil }),
        openFiles: any OpenFileSnapshotProviding = CountingSnapshotProvider(snapshot: .nothingOpen),
        runningApps: any RunningAppsProviding = FixedRunningAppsList(apps: []),
        freeSpace: any VolumeFreeSpaceProviding = FixedFreeSpace(reading: nil),
        runningExecutables: any RunningExecutablesProviding = FixedRunningExecutables(paths: []),
        isCodexRunning: @escaping @Sendable () async -> Bool = { false },
        pnpmActiveStore: @escaping @Sendable () async -> URL? = { nil }
    ) -> CleanupEngine {
        CleanupEngine(
            store: store,
            projectRootsProvider: projectRootsProvider,
            exclusionsProvider: exclusionsProvider,
            now: now,
            trashItem: trashItem,
            gitInspector: gitInspector,
            goCacheLocations: goCacheLocations,
            openFiles: openFiles,
            runningApps: runningApps,
            freeSpace: freeSpace,
            runningExecutables: runningExecutables,
            isCodexRunning: isCodexRunning,
            pnpmActiveStore: pnpmActiveStore
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

/// A fixed process list; nil is "could not list processes".
struct FixedRunningExecutables: RunningExecutablesProviding {
    let paths: [String]?

    func runningExecutablePaths() async -> [String]? { paths }
}
