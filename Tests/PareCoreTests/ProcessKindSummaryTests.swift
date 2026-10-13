import XCTest
@testable import PareCore

final class ProcessKindSummaryTests: XCTestCase {

    private func input(_ pid: Int32, parent: Int32, name: String, mb: UInt64, residentMB: UInt64) -> ProcessTreeBuilder.Input {
        ProcessTreeBuilder.Input(
            record: ProcessRecord(
                id: ProcessID(pid: pid, startMicros: 1),
                parentPID: parent,
                kernelName: "node",
                executablePath: nil,
                footprintBytes: mb << 20,
                residentBytes: residentMB << 20,
                cpuTimeNanos: 0
            ),
            identity: ProcessIdentity(displayName: name, executableName: "node"),
            cpuPercent: nil,
            paseoAgent: nil
        )
    }

    /// Daemon → three agents, each with one graph server and one gitnexus server; plus a lone big app.
    private var tree: ProcessTree {
        var inputs = [
            input(1, parent: 0, name: "Paseo Daemon", mb: 150, residentMB: 120),
            input(500, parent: 0, name: "Xcode", mb: 1_300, residentMB: 700),
            input(600, parent: 0, name: "zsh", mb: 5, residentMB: 4),
            input(601, parent: 0, name: "zsh", mb: 5, residentMB: 4)
        ]
        for agent in Int32(0)..<3 {
            let agentPID = 10 + agent * 10
            inputs.append(input(agentPID, parent: 1, name: "Claude Code", mb: 300, residentMB: 90))
            inputs.append(input(agentPID + 1, parent: agentPID, name: "code-review-graph serve", mb: 80, residentMB: 20))
            inputs.append(input(agentPID + 2, parent: agentPID, name: "gitnexus mcp", mb: 45, residentMB: 15))
        }
        return ProcessTreeBuilder.build(inputs)
    }

    func testTotalsGroupByDerivedNameAcrossBranches() {
        let kinds = ProcessKindSummary.totals(tree.roots)
        let graph = kinds.first { $0.name == "code-review-graph serve" }

        XCTAssertEqual(graph, ProcessKindTotal(name: "code-review-graph serve", processCount: 3,
                                               footprintBytes: 240 << 20, residentBytes: 60 << 20))
        XCTAssertEqual(kinds.first { $0.name == "Claude Code" }?.processCount, 3)
        XCTAssertEqual(kinds.reduce(0) { $0 + $1.processCount }, tree.processCount)
        XCTAssertEqual(kinds.reduce(0) { $0 + $1.residentBytes }, tree.totalResidentBytes)
    }

    func testTotalsAreSortedByFootprintThenCountThenName() {
        let kinds = ProcessKindSummary.totals(tree.roots)

        XCTAssertEqual(kinds.map(\.name), [
            "Xcode", "Claude Code", "code-review-graph serve", "Paseo Daemon", "gitnexus mcp", "zsh"
        ])
    }

    func testTopKeepsOnlyRepeatedKindsOverTheFootprintFloor() {
        let top = ProcessKindSummary.top(in: tree)

        // Xcode is heavy but single; zsh repeats but is tiny.
        XCTAssertEqual(top.map(\.name), ["Claude Code", "code-review-graph serve", "gitnexus mcp"])
        XCTAssertTrue(top.allSatisfy { $0.residentBytes < $0.footprintBytes })
    }

    func testTopHonoursThresholdsAndLimit() {
        XCTAssertEqual(ProcessKindSummary.top(in: tree, minFootprintBytes: 200 << 20).map(\.name),
                       ["Claude Code", "code-review-graph serve"])
        XCTAssertEqual(ProcessKindSummary.top(in: tree, minProcessCount: 1, minFootprintBytes: 0, limit: 2).map(\.name),
                       ["Xcode", "Claude Code"])
        XCTAssertEqual(ProcessKindSummary.top(in: tree, limit: 0), [])
    }

    func testEmptyTreeHasNoKinds() {
        XCTAssertEqual(ProcessKindSummary.totals([]), [])
        XCTAssertEqual(ProcessKindSummary.top(in: .empty), [])
    }
}
