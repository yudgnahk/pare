import Foundation

/// A process instance: the pid plus its start time, so a reused pid is a different process.
public struct ProcessID: Hashable, Sendable, Comparable {
    public let pid: Int32
    /// Microseconds since 1970 at process start.
    public let startMicros: UInt64

    public init(pid: Int32, startMicros: UInt64) {
        self.pid = pid
        self.startMicros = startMicros
    }

    public static func < (lhs: ProcessID, rhs: ProcessID) -> Bool {
        (lhs.pid, lhs.startMicros) < (rhs.pid, rhs.startMicros)
    }
}

/// One process of the current user as read from the kernel; never carries arguments.
public struct ProcessRecord: Sendable, Equatable {
    public let id: ProcessID
    public let parentPID: Int32
    /// Kernel process name (`pbi_name`, falling back to `pbi_comm`).
    public let kernelName: String
    public let executablePath: String?
    /// `phys_footprint`, the figure Activity Monitor shows as Memory.
    public let footprintBytes: UInt64
    /// Pages in RAM right now; compressed and swapped-out memory counts in the footprint but not here.
    public let residentBytes: UInt64
    /// User plus system CPU time, in nanoseconds.
    public let cpuTimeNanos: UInt64

    public init(
        id: ProcessID,
        parentPID: Int32,
        kernelName: String,
        executablePath: String?,
        footprintBytes: UInt64,
        residentBytes: UInt64,
        cpuTimeNanos: UInt64
    ) {
        self.id = id
        self.parentPID = parentPID
        self.kernelName = kernelName
        self.executablePath = executablePath
        self.footprintBytes = footprintBytes
        self.residentBytes = residentBytes
        self.cpuTimeNanos = cpuTimeNanos
    }
}

/// What a process is called, derived once from its arguments; the arguments themselves are dropped.
public struct ProcessIdentity: Sendable, Equatable {
    public let displayName: String
    /// Basename of the executable, e.g. `node` behind `gitnexus mcp`.
    public let executableName: String
    public let paseoAgentID: UUID?

    public init(displayName: String, executableName: String, paseoAgentID: UUID? = nil) {
        self.displayName = displayName
        self.executableName = executableName
        self.paseoAgentID = paseoAgentID
    }
}

/// A Paseo agent session, read from `~/.paseo/agents/<cwd-slug>/<uuid>.json`.
public struct PaseoAgentInfo: Sendable, Equatable {
    public let title: String?
    public let cwd: String?
    public let lastStatus: String?
    public let lastUserMessageAt: Date?

    public init(title: String?, cwd: String?, lastStatus: String?, lastUserMessageAt: Date?) {
        self.title = title
        self.cwd = cwd
        self.lastStatus = lastStatus
        self.lastUserMessageAt = lastUserMessageAt
    }

    /// `~/Projects/a/b/c` → `~/…/b/c`: enough to tell sibling projects apart.
    public func abbreviatedCwd(homeDirectory: String = NSHomeDirectory()) -> String? {
        guard let cwd, !cwd.isEmpty else { return nil }
        var path = cwd
        let home = homeDirectory.hasSuffix("/") ? String(homeDirectory.dropLast()) : homeDirectory
        var prefix = ""
        if !home.isEmpty, path == home || path.hasPrefix(home + "/") {
            path = String(path.dropFirst(home.count))
            prefix = "~"
        }
        let components = path.split(separator: "/").map(String.init)
        guard components.count > 2 else { return prefix + (path.isEmpty ? "" : path) }
        return prefix + "/…/" + components.suffix(2).joined(separator: "/")
    }
}

/// A process with its subtree; branch totals include the process itself.
public struct ProcessNode: Sendable, Equatable, Identifiable {
    public let id: ProcessID
    public let name: String
    public let executableName: String
    public let footprintBytes: UInt64
    public let residentBytes: UInt64
    /// Nil until two samples exist.
    public let cpuPercent: Double?
    public let branchFootprintBytes: UInt64
    public let branchResidentBytes: UInt64
    public let branchCPUPercent: Double?
    public let descendantCount: Int
    public let paseoAgent: PaseoAgentInfo?
    public let children: [ProcessNode]

    public init(
        id: ProcessID,
        name: String,
        executableName: String,
        footprintBytes: UInt64,
        residentBytes: UInt64,
        cpuPercent: Double?,
        branchFootprintBytes: UInt64,
        branchResidentBytes: UInt64,
        branchCPUPercent: Double?,
        descendantCount: Int,
        paseoAgent: PaseoAgentInfo?,
        children: [ProcessNode]
    ) {
        self.id = id
        self.name = name
        self.executableName = executableName
        self.footprintBytes = footprintBytes
        self.residentBytes = residentBytes
        self.cpuPercent = cpuPercent
        self.branchFootprintBytes = branchFootprintBytes
        self.branchResidentBytes = branchResidentBytes
        self.branchCPUPercent = branchCPUPercent
        self.descendantCount = descendantCount
        self.paseoAgent = paseoAgent
        self.children = children
    }
}

/// Every process of the current user, as a forest sorted by branch memory.
public struct ProcessTree: Sendable, Equatable {
    public let roots: [ProcessNode]
    public let processCount: Int
    public let totalFootprintBytes: UInt64
    public let totalResidentBytes: UInt64
    public let totalCPUPercent: Double?

    public init(roots: [ProcessNode]) {
        self.roots = roots
        self.processCount = roots.reduce(0) { $0 + 1 + $1.descendantCount }
        self.totalFootprintBytes = roots.reduce(0) { $0 + $1.branchFootprintBytes }
        self.totalResidentBytes = roots.reduce(0) { $0 + $1.branchResidentBytes }
        self.totalCPUPercent = ProcessCPUUsage.sum(roots.map(\.branchCPUPercent))
    }

    public static let empty = ProcessTree(roots: [])
}
