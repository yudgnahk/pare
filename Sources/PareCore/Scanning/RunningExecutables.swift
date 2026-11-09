import Darwin
import Foundation

/// Absolute paths of executables running right now; nil when the snapshot is unavailable.
public protocol RunningExecutablesProviding: Sendable {
    func runningExecutablePaths() async -> [String]?
}

/// Every process's executable from `proc_pidpath`: the kernel's path of the running image, so processes `ps`
/// shows without a path are covered and a launcher symlink later repointed cannot hide the old version.
public struct LibprocRunningExecutablesProvider: RunningExecutablesProviding {
    private static let pathBufferSize = 4 * Int(MAXPATHLEN) // PROC_PIDPATHINFO_MAXSIZE

    private let listPIDs: @Sendable () -> [pid_t]?
    private let pathForPID: @Sendable (pid_t) -> String?

    public init() {
        self.init(listPIDs: { Self.allPIDs() }, pathForPID: { Self.executablePath($0) })
    }

    /// Tests inject a failing pid listing or canned paths.
    init(listPIDs: @escaping @Sendable () -> [pid_t]?, pathForPID: @escaping @Sendable (pid_t) -> String?) {
        self.listPIDs = listPIDs
        self.pathForPID = pathForPID
    }

    public func runningExecutablePaths() async -> [String]? {
        guard let pids = listPIDs() else { return nil }
        let paths = Set(pids.compactMap(pathForPID).filter { $0.hasPrefix("/") })
        // No path at all is not a real process list; treat it as unavailable.
        return paths.isEmpty ? nil : paths.sorted()
    }

    static func allPIDs() -> [pid_t]? {
        let estimate = proc_listallpids(nil, 0)
        guard estimate > 0 else { return nil }
        // Headroom for processes spawned between the two calls.
        var pids = [pid_t](repeating: 0, count: Int(estimate) + 256)
        let count = pids.withUnsafeMutableBytes { buffer in
            proc_listallpids(buffer.baseAddress, Int32(buffer.count))
        }
        guard count > 0 else { return nil }
        return pids.prefix(Int(count)).filter { $0 > 0 }
    }

    static func executablePath(_ pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: pathBufferSize)
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        return String(cString: buffer)
    }
}
