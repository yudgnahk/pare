import AppKit
import Foundation

/// Free bytes on the volume holding a path; nil when unknown (callers fail closed).
public protocol FreeSpaceProviding: Sendable {
    func availableBytes(atPath path: String) -> Int64?
}

/// Whether an app with the given bundle identifier is currently running.
public protocol RunningAppChecking: Sendable {
    func isRunning(bundleIdentifier: String) -> Bool
}

/// `statfs` free blocks available to unprivileged users.
public struct StatfsFreeSpace: FreeSpaceProviding {
    public init() {}

    public func availableBytes(atPath path: String) -> Int64? {
        var stats = statfs()
        guard statfs(path, &stats) == 0 else { return nil }
        return Int64(stats.f_bavail) * Int64(stats.f_bsize)
    }
}

public struct WorkspaceRunningApps: RunningAppChecking {
    public init() {}

    public func isRunning(bundleIdentifier: String) -> Bool {
        NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == bundleIdentifier }
    }
}
