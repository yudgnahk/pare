import XCTest
import PareCore
@testable import PareApp

@MainActor
final class ProcessMonitorViewModelTests: XCTestCase {

    private func node(_ pid: Int32, children: [ProcessNode] = []) -> ProcessNode {
        ProcessNode(
            id: ProcessID(pid: pid, startMicros: 1),
            name: "p\(pid)",
            executableName: "p\(pid)",
            footprintBytes: 1,
            residentBytes: 1,
            cpuPercent: nil,
            branchFootprintBytes: 1,
            branchResidentBytes: 1,
            branchCPUPercent: nil,
            descendantCount: children.count,
            paseoAgent: nil,
            children: children
        )
    }

    func testFlattenDescendsOnlyIntoExpandedNodes() {
        let tree = [node(1, children: [node(2, children: [node(3)]), node(4)]), node(5)]

        let collapsed = ProcessRow.flatten(tree, expanded: [])
        XCTAssertEqual(collapsed.map(\.id.pid), [1, 5])

        let expanded = ProcessRow.flatten(tree, expanded: [ProcessID(pid: 1, startMicros: 1)])
        XCTAssertEqual(expanded.map(\.id.pid), [1, 2, 4, 5])
        XCTAssertEqual(expanded.map(\.depth), [0, 1, 1, 0])
        XCTAssertTrue(expanded[0].isExpanded)
        XCTAssertTrue(expanded[1].hasChildren)
        XCTAssertFalse(expanded[1].isExpanded)
    }

    func testToggleExpandsAndCollapses() {
        let model = ProcessMonitorViewModel(monitor: ProcessMonitor(provider: EmptyProvider(), paseo: nil))
        let id = ProcessID(pid: 7, startMicros: 1)

        model.toggle(id)
        XCTAssertTrue(model.expanded.contains(id))
        model.toggle(id)
        XCTAssertFalse(model.expanded.contains(id))
    }

    func testRefreshPublishesTreeAndStopEndsSampling() async {
        let model = ProcessMonitorViewModel(monitor: ProcessMonitor(provider: EmptyProvider(), paseo: nil))

        await model.refreshOnce()
        XCTAssertEqual(model.state, .loaded)
        XCTAssertEqual(model.tree, .empty)

        model.start()
        XCTAssertTrue(model.isRefreshing)
        model.stop()
        XCTAssertFalse(model.isRefreshing)
    }

    func testSnapshotFixtureIsAPopulatedTreeUnderTheFakeRoot() {
        let tree = SnapshotFixtures.processTree

        XCTAssertGreaterThan(tree.processCount, 10)
        let agents = tree.roots.flatMap(\.children).compactMap(\.paseoAgent)
        XCTAssertFalse(agents.isEmpty)
        for agent in agents {
            XCTAssertTrue(agent.cwd?.hasPrefix(SnapshotFixtures.root + "/") == true, agent.cwd ?? "nil")
        }
        XCTAssertLessThan(tree.totalResidentBytes, tree.totalFootprintBytes)
    }

    func testPinnedTreePublishesRepeatedKinds() {
        let model = ProcessMonitorViewModel(monitor: ProcessMonitor(provider: EmptyProvider(), paseo: nil))

        model.applySnapshotTree(SnapshotFixtures.processTree, expanded: [])

        XCTAssertEqual(Set(model.kinds.map(\.name)), ["Claude Code", "gitnexus mcp", "code-review-graph serve"])
        XCTAssertEqual(model.kinds.first?.name, "Claude Code")
        XCTAssertTrue(model.kinds.allSatisfy { $0.processCount == 3 })
    }
}

private struct EmptyProvider: ProcessSnapshotProviding {
    func listProcesses() throws -> [ProcessRecord] { [] }
    func arguments(of pid: Int32) -> [String]? { nil }
}
