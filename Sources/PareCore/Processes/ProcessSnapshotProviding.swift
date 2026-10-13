import Foundation

/// Source of the current user's processes.
public protocol ProcessSnapshotProviding: Sendable {
    /// Every live, non-zombie process owned by the current user.
    func listProcesses() throws -> [ProcessRecord]
    /// Raw argv, read only to name a process; callers must not keep it.
    func arguments(of pid: Int32) -> [String]?
}

public enum ProcessSnapshotError: Error, Equatable, LocalizedError {
    case listingFailed(errno: Int32)

    public var errorDescription: String? {
        switch self {
        case .listingFailed:
            return "Could not read the list of running processes."
        }
    }
}
