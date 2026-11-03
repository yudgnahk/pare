import Foundation

/// Every process sharing one derived name, e.g. twenty `code-review-graph serve` servers.
public struct ProcessKindTotal: Sendable, Equatable, Identifiable {
    public let name: String
    public let processCount: Int
    public let footprintBytes: UInt64
    public let residentBytes: UInt64

    public var id: String { name }

    public init(name: String, processCount: Int, footprintBytes: UInt64, residentBytes: UInt64) {
        self.name = name
        self.processCount = processCount
        self.footprintBytes = footprintBytes
        self.residentBytes = residentBytes
    }
}

/// Totals per derived process name across the whole forest, wherever each copy sits in the tree.
public enum ProcessKindSummary {
    /// A single process is already one row in the tree; the summary is for repeats.
    public static let minProcessCount = 2
    public static let minFootprintBytes: UInt64 = 100 << 20
    public static let maxKinds = 6

    /// Repeated kinds heavy enough to matter, heaviest first.
    public static func top(
        in tree: ProcessTree,
        minProcessCount: Int = minProcessCount,
        minFootprintBytes: UInt64 = minFootprintBytes,
        limit: Int = maxKinds
    ) -> [ProcessKindTotal] {
        let kinds = totals(tree.roots).filter {
            $0.processCount >= minProcessCount && $0.footprintBytes >= minFootprintBytes
        }
        return Array(kinds.prefix(max(0, limit)))
    }

    /// Every kind, sorted by footprint, then process count, then name.
    public static func totals(_ roots: [ProcessNode]) -> [ProcessKindTotal] {
        var byName: [String: ProcessKindTotal] = [:]
        var pending = roots
        while let node = pending.popLast() {
            let current = byName[node.name]
            byName[node.name] = ProcessKindTotal(
                name: node.name,
                processCount: (current?.processCount ?? 0) + 1,
                footprintBytes: (current?.footprintBytes ?? 0) + node.footprintBytes,
                residentBytes: (current?.residentBytes ?? 0) + node.residentBytes
            )
            pending.append(contentsOf: node.children)
        }
        return byName.values.sorted {
            if $0.footprintBytes != $1.footprintBytes { return $0.footprintBytes > $1.footprintBytes }
            if $0.processCount != $1.processCount { return $0.processCount > $1.processCount }
            return $0.name < $1.name
        }
    }
}
