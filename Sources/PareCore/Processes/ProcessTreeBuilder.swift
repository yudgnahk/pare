import Foundation

/// Builds the parent/child forest from flat records; pure and cycle-safe.
public enum ProcessTreeBuilder {
    public struct Input: Sendable, Equatable {
        public let record: ProcessRecord
        public let identity: ProcessIdentity
        public let cpuPercent: Double?
        public let paseoAgent: PaseoAgentInfo?

        public init(record: ProcessRecord, identity: ProcessIdentity, cpuPercent: Double?, paseoAgent: PaseoAgentInfo?) {
            self.record = record
            self.identity = identity
            self.cpuPercent = cpuPercent
            self.paseoAgent = paseoAgent
        }
    }

    /// A process whose parent is missing (other user, exited, or itself) becomes a root.
    public static func build(_ inputs: [Input]) -> ProcessTree {
        var byPID: [Int32: Input] = [:]
        for input in inputs where byPID[input.record.id.pid] == nil {
            byPID[input.record.id.pid] = input
        }
        let parentOf = effectiveParents(byPID)
        var childrenOf: [Int32: [Int32]] = [:]
        var rootPIDs: [Int32] = []
        for pid in byPID.keys {
            if let parent = parentOf[pid] {
                childrenOf[parent, default: []].append(pid)
            } else {
                rootPIDs.append(pid)
            }
        }
        let roots = rootPIDs.map { node(for: $0, byPID: byPID, childrenOf: childrenOf) }
        return ProcessTree(roots: sorted(roots))
    }

    /// Parent pid per process, with every ppid loop cut at its lowest pid so recursion terminates.
    private static func effectiveParents(_ byPID: [Int32: Input]) -> [Int32: Int32] {
        var parentOf: [Int32: Int32] = [:]
        for (pid, input) in byPID {
            let ppid = input.record.parentPID
            if ppid != pid, byPID[ppid] != nil { parentOf[pid] = ppid }
        }
        var settled: Set<Int32> = []
        for start in byPID.keys.sorted() where !settled.contains(start) {
            var path: [Int32] = []
            var onPath: Set<Int32> = []
            var cursor: Int32? = start
            while let pid = cursor, !settled.contains(pid) {
                if onPath.contains(pid) {
                    let loop = path[path.firstIndex(of: pid)!...]
                    parentOf[loop.min()!] = nil
                    break
                }
                path.append(pid)
                onPath.insert(pid)
                cursor = parentOf[pid]
            }
            settled.formUnion(path)
        }
        return parentOf
    }

    private static func node(for pid: Int32, byPID: [Int32: Input], childrenOf: [Int32: [Int32]]) -> ProcessNode {
        let input = byPID[pid]!
        let children = sorted((childrenOf[pid] ?? []).map { node(for: $0, byPID: byPID, childrenOf: childrenOf) })
        return ProcessNode(
            id: input.record.id,
            name: input.identity.displayName,
            executableName: input.identity.executableName,
            footprintBytes: input.record.footprintBytes,
            residentBytes: input.record.residentBytes,
            cpuPercent: input.cpuPercent,
            branchFootprintBytes: children.reduce(input.record.footprintBytes) { $0 + $1.branchFootprintBytes },
            branchResidentBytes: children.reduce(input.record.residentBytes) { $0 + $1.branchResidentBytes },
            branchCPUPercent: ProcessCPUUsage.sum([input.cpuPercent] + children.map(\.branchCPUPercent)),
            descendantCount: children.reduce(0) { $0 + 1 + $1.descendantCount },
            paseoAgent: input.paseoAgent,
            children: children
        )
    }

    private static func sorted(_ nodes: [ProcessNode]) -> [ProcessNode] {
        nodes.sorted {
            if $0.branchFootprintBytes != $1.branchFootprintBytes {
                return $0.branchFootprintBytes > $1.branchFootprintBytes
            }
            return $0.id < $1.id
        }
    }
}
