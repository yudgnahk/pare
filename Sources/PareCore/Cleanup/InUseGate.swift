import AppKit
import Foundation
import os

/// A running app, for matching `~/Library/Caches/<bundle id>` folders.
public struct RunningApp: Sendable, Equatable {
    public let bundleIdentifier: String
    public let name: String

    public init(bundleIdentifier: String, name: String) {
        self.bundleIdentifier = bundleIdentifier
        self.name = name
    }
}

public protocol RunningAppsProviding: Sendable {
    func runningApps() -> [RunningApp]
}

public struct WorkspaceRunningAppsProvider: RunningAppsProviding {
    public init() {}

    public func runningApps() -> [RunningApp] {
        NSWorkspace.shared.runningApplications.compactMap { app in
            app.bundleIdentifier.map { RunningApp(bundleIdentifier: $0, name: app.localizedName ?? $0) }
        }
    }
}

/// Decides whether a cleanup item is in use by another process.
public enum InUseGate {
    static let sqliteFileSuffixes = [".db", ".sqlite", ".sqlite3", "-wal", "-shm", "-journal"]

    static let unavailableProjectHolder = "the project may be in use (open-file check unavailable)"

    /// The holder blocking `path`, or nil. With a snapshot, any open file at or under the path blocks it.
    /// Without one, only items where trashing a live file does damage fail closed; the rest fail open.
    public static func holder(
        forPath path: String,
        snapshot: OpenFileSnapshot?,
        failClosedWithoutSnapshot: Bool = false,
        runningApps: () -> [RunningApp]
    ) -> String? {
        if let snapshot { return snapshot.holder(atOrUnder: path) }
        // A project's dev server keeps nothing open under `/library/caches/`, so the heuristics below would pass it.
        if failClosedWithoutSnapshot { return unavailableProjectHolder }

        let lower = path.lowercased()
        let name = URL(fileURLWithPath: lower).lastPathComponent
        if name.hasSuffix(".incomplete") {
            return "a download may still be in progress (open-file check unavailable)"
        }
        guard let caches = lower.range(of: "/library/caches/") else { return nil }
        if sqliteFileSuffixes.contains(where: { name.hasSuffix($0) }) {
            return "a cached database may be open (open-file check unavailable)"
        }
        let cacheFolder = lower[caches.upperBound...].split(separator: "/").first.map(String.init)
        guard let cacheFolder,
              let app = runningApps().first(where: { $0.bundleIdentifier.lowercased() == cacheFolder }) else { return nil }
        return "\(app.name) is running (open-file check unavailable)"
    }
}

/// Per-cleanup-batch state: the snapshot and app list are taken on first use, never per item, and the
/// snapshot is re-taken once it is older than `snapshotRefreshInterval` (a long batch must not trust it).
actor InUseBatchCheck {
    static let logger = Logger(subsystem: "Pare", category: "cleanup")
    /// How long one open-file snapshot is trusted before the next trash step takes a fresh one.
    static let snapshotRefreshInterval: TimeInterval = 30

    private let openFiles: any OpenFileSnapshotProviding
    private let runningAppsProvider: any RunningAppsProviding
    private let log: @Sendable (String) -> Void
    private let now: @Sendable () -> Date
    private let refreshInterval: TimeInterval
    private var snapshot: OpenFileSnapshot??
    private var snapshotTakenAt: Date?
    private var apps: [RunningApp]?
    /// True once any snapshot in this batch was unavailable, so the result can say so.
    private(set) var snapshotWasUnavailable = false

    init(
        openFiles: any OpenFileSnapshotProviding,
        runningApps: any RunningAppsProviding,
        now: @escaping @Sendable () -> Date = { Date() },
        refreshInterval: TimeInterval = InUseBatchCheck.snapshotRefreshInterval,
        log: @escaping @Sendable (String) -> Void = { InUseBatchCheck.logger.notice("\($0, privacy: .public)") }
    ) {
        self.openFiles = openFiles
        self.runningAppsProvider = runningApps
        self.now = now
        self.refreshInterval = refreshInterval
        self.log = log
    }

    func holder(forPath path: String, failClosedWithoutSnapshot: Bool = false) async -> String? {
        let isStale = snapshotTakenAt.map { now().timeIntervalSince($0) >= refreshInterval } ?? true
        if snapshot == nil || isStale {
            let taken = await openFiles.snapshot()
            if taken == nil {
                snapshotWasUnavailable = true
                log("Open-file snapshot unavailable; only risky cache items are held back")
            }
            snapshot = .some(taken)
            snapshotTakenAt = now()
        }
        return InUseGate.holder(
            forPath: path, snapshot: snapshot ?? nil, failClosedWithoutSnapshot: failClosedWithoutSnapshot
        ) {
            if let apps { return apps }
            let current = runningAppsProvider.runningApps()
            apps = current
            return current
        }
    }
}
