import XCTest
@testable import PareCore

final class ProcessTreeBuilderTests: XCTestCase {

    private func input(_ pid: Int32, parent: Int32, mb: UInt64 = 1, residentMB: UInt64? = nil, cpu: Double? = nil) -> ProcessTreeBuilder.Input {
        ProcessTreeBuilder.Input(
            record: ProcessRecord(
                id: ProcessID(pid: pid, startMicros: 1),
                parentPID: parent,
                kernelName: "p\(pid)",
                executablePath: nil,
                footprintBytes: mb << 20,
                residentBytes: (residentMB ?? mb) << 20,
                cpuTimeNanos: 0
            ),
            identity: ProcessIdentity(displayName: "p\(pid)", executableName: "p\(pid)"),
            cpuPercent: cpu,
            paseoAgent: nil
        )
    }

    private func allPIDs(_ nodes: [ProcessNode]) -> [Int32] {
        nodes.flatMap { [$0.id.pid] + allPIDs($0.children) }
    }

    func testProcessWithMissingParentBecomesRoot() {
        let tree = ProcessTreeBuilder.build([input(10, parent: 1), input(11, parent: 10), input(20, parent: 999)])

        XCTAssertEqual(Set(tree.roots.map(\.id.pid)), [10, 20])
        XCTAssertEqual(tree.roots.first { $0.id.pid == 10 }?.children.map(\.id.pid), [11])
        XCTAssertEqual(tree.processCount, 3)
    }

    func testSelfParentedProcessIsRoot() {
        let tree = ProcessTreeBuilder.build([input(5, parent: 5)])

        XCTAssertEqual(tree.roots.map(\.id.pid), [5])
        XCTAssertTrue(tree.roots[0].children.isEmpty)
    }

    func testParentCycleTerminatesAndKeepsEveryProcessOnce() {
        // 30 → 31 → 32 → 30, plus 33 hanging off the loop.
        let tree = ProcessTreeBuilder.build([
            input(30, parent: 32), input(31, parent: 30), input(32, parent: 31), input(33, parent: 31)
        ])

        XCTAssertEqual(allPIDs(tree.roots).sorted(), [30, 31, 32, 33])
        XCTAssertEqual(tree.roots.map(\.id.pid), [30], "the loop is cut at its lowest pid")
        XCTAssertEqual(tree.processCount, 4)
    }

    func testTwoProcessCycleIsCut() {
        let tree = ProcessTreeBuilder.build([input(41, parent: 40), input(40, parent: 41)])

        XCTAssertEqual(tree.roots.map(\.id.pid), [40])
        XCTAssertEqual(tree.roots[0].children.map(\.id.pid), [41])
    }

    func testBranchTotalsIncludeEveryDescendant() {
        let tree = ProcessTreeBuilder.build([
            input(1, parent: 0, mb: 100, cpu: 2),
            input(2, parent: 1, mb: 200, cpu: 10),
            input(3, parent: 2, mb: 50, cpu: nil),
            input(4, parent: 1, mb: 25, cpu: 1.5)
        ])
        let root = tree.roots[0]

        XCTAssertEqual(root.footprintBytes, 100 << 20)
        XCTAssertEqual(root.branchFootprintBytes, 375 << 20)
        XCTAssertEqual(root.branchCPUPercent ?? -1, 13.5, accuracy: 0.0001)
        XCTAssertEqual(root.descendantCount, 3)
        XCTAssertEqual(tree.totalFootprintBytes, 375 << 20)
        XCTAssertEqual(tree.totalCPUPercent ?? -1, 13.5, accuracy: 0.0001)
    }

    func testBranchAndTreeTotalsAddResidentSeparatelyFromFootprint() throws {
        // Idle children mostly compressed: resident well under footprint.
        let tree = ProcessTreeBuilder.build([
            input(1, parent: 0, mb: 100, residentMB: 80),
            input(2, parent: 1, mb: 200, residentMB: 30),
            input(3, parent: 2, mb: 50, residentMB: 10),
            input(9, parent: 0, mb: 40, residentMB: 40)
        ])
        let root = try XCTUnwrap(tree.roots.first { $0.id.pid == 1 })

        XCTAssertEqual(root.residentBytes, 80 << 20)
        XCTAssertEqual(root.branchResidentBytes, 120 << 20)
        XCTAssertEqual(root.children[0].branchResidentBytes, 40 << 20)
        XCTAssertEqual(root.branchFootprintBytes, 350 << 20)
        XCTAssertLessThan(root.branchResidentBytes, root.branchFootprintBytes)
        XCTAssertEqual(tree.totalResidentBytes, 160 << 20)
        XCTAssertEqual(tree.totalFootprintBytes, 390 << 20)
    }

    func testCPUStaysUnknownUntilAnyValueIsKnown() {
        let tree = ProcessTreeBuilder.build([input(1, parent: 0), input(2, parent: 1)])

        XCTAssertNil(tree.roots[0].branchCPUPercent)
        XCTAssertNil(tree.totalCPUPercent)
    }

    func testRootsAndChildrenAreSortedByBranchMemory() {
        let tree = ProcessTreeBuilder.build([
            input(1, parent: 0, mb: 10),
            input(2, parent: 0, mb: 5),
            input(3, parent: 2, mb: 50),
            input(4, parent: 1, mb: 1),
            input(5, parent: 1, mb: 3)
        ])

        XCTAssertEqual(tree.roots.map(\.id.pid), [2, 1])
        XCTAssertEqual(tree.roots[1].children.map(\.id.pid), [5, 4])
    }

    func testEmptyInputIsEmptyTree() {
        XCTAssertEqual(ProcessTreeBuilder.build([]), .empty)
    }
}
