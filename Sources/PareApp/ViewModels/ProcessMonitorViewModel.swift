import Foundation
import PareCore

/// Drives the Processes tab; samples only while the tab is on screen.
@MainActor
final class ProcessMonitorViewModel: ObservableObject {
    static let refreshIntervalNanos: UInt64 = 2_500_000_000

    @Published private(set) var tree: ProcessTree = .empty
    @Published private(set) var state: LoadState = .idle
    @Published private(set) var expanded: Set<ProcessID> = []

    private let monitor: ProcessMonitor
    private var refreshTask: Task<Void, Never>?

    init(monitor: ProcessMonitor = ProcessMonitor()) {
        self.monitor = monitor
    }

    var rows: [ProcessRow] {
        ProcessRow.flatten(tree.roots, expanded: expanded)
    }

    var isRefreshing: Bool { refreshTask != nil }

    func start() {
        #if DEBUG
        guard !isSnapshotPinned else { return }
        #endif
        guard refreshTask == nil else { return }
        if tree.roots.isEmpty { state = .loading }
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshOnce()
                try? await Task.sleep(nanoseconds: Self.refreshIntervalNanos)
            }
        }
    }

    func stop() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    func refreshOnce() async {
        do {
            let tree = try await monitor.refresh()
            guard !Task.isCancelled else { return }
            self.tree = tree
            state = .loaded
        } catch {
            NSLog("Process sampling failed: \(error.localizedDescription)")
            state = .error("Could not read running processes. Pare will keep trying.")
        }
    }

    func toggle(_ id: ProcessID) {
        if expanded.contains(id) {
            expanded.remove(id)
        } else {
            expanded.insert(id)
        }
    }

    #if DEBUG
    private var isSnapshotPinned = false

    /// Snapshot renderer pins a fixture tree so appearing never samples real processes.
    func applySnapshotTree(_ fixture: ProcessTree, expanded ids: Set<ProcessID>) {
        isSnapshotPinned = true
        tree = fixture
        expanded = ids
        state = .loaded
    }
    #endif
}

/// One visible line of the outline.
struct ProcessRow: Identifiable, Equatable {
    let node: ProcessNode
    let depth: Int
    let isExpanded: Bool

    var id: ProcessID { node.id }
    var hasChildren: Bool { !node.children.isEmpty }

    /// Depth-first rows, descending only into expanded nodes.
    static func flatten(_ nodes: [ProcessNode], expanded: Set<ProcessID>, depth: Int = 0) -> [ProcessRow] {
        nodes.flatMap { node -> [ProcessRow] in
            let isExpanded = expanded.contains(node.id)
            let row = ProcessRow(node: node, depth: depth, isExpanded: isExpanded)
            guard isExpanded else { return [row] }
            return [row] + flatten(node.children, expanded: expanded, depth: depth + 1)
        }
    }
}
