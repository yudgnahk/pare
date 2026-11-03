import XCTest
@testable import PareCore

final class ProcessCPUUsageTests: XCTestCase {

    private let a = ProcessID(pid: 1, startMicros: 100)
    private let b = ProcessID(pid: 2, startMicros: 100)

    func testPercentIsCPUTimeOverWallTime() {
        let result = ProcessCPUUsage.percentages(
            previous: [a: 1_000_000_000, b: 0],
            current: [a: 1_500_000_000, b: 4_000_000_000],
            elapsedNanos: 2_000_000_000
        )

        XCTAssertEqual(result[a] ?? -1, 25, accuracy: 0.0001)
        XCTAssertEqual(result[b] ?? -1, 200, accuracy: 0.0001, "two busy cores read as 200%, like Activity Monitor")
    }

    func testProcessWithoutPreviousSampleHasNoValue() {
        let result = ProcessCPUUsage.percentages(previous: [:], current: [a: 5], elapsedNanos: 1_000)

        XCTAssertNil(result[a])
    }

    func testReusedPIDIsNotComparedWithTheOldProcess() {
        let reused = ProcessID(pid: 1, startMicros: 999)
        let result = ProcessCPUUsage.percentages(previous: [a: 0], current: [reused: 9_000_000_000], elapsedNanos: 1_000_000_000)

        XCTAssertNil(result[reused])
    }

    func testCounterGoingBackwardsReadsAsZero() {
        let result = ProcessCPUUsage.percentages(previous: [a: 10_000], current: [a: 5_000], elapsedNanos: 1_000)

        XCTAssertEqual(result[a], 0)
    }

    func testZeroElapsedTimeYieldsNothing() {
        XCTAssertTrue(ProcessCPUUsage.percentages(previous: [a: 0], current: [a: 10], elapsedNanos: 0).isEmpty)
    }
}

final class ProcessArgumentsParserTests: XCTestCase {

    private func buffer(argc: Int32, exec: String, padding: Int, args: [String], env: [String] = []) -> [UInt8] {
        var bytes = withUnsafeBytes(of: argc) { Array($0) }
        bytes += Array(exec.utf8) + [0] + Array(repeating: 0, count: padding)
        for value in args + env {
            bytes += Array(value.utf8) + [0]
        }
        return bytes
    }

    func testParsesArgvAndStopsBeforeEnvironment() {
        let bytes = buffer(argc: 3, exec: "/usr/bin/node", padding: 5, args: ["node", "/x/gitnexus", "mcp"], env: ["SECRET=1"])

        XCTAssertEqual(ProcessArgumentsParser.parse(bytes), ["node", "/x/gitnexus", "mcp"])
    }

    func testRejectsImplausibleArgc() {
        XCTAssertNil(ProcessArgumentsParser.parse(buffer(argc: 0, exec: "/bin/x", padding: 1, args: [])))
        XCTAssertNil(ProcessArgumentsParser.parse(buffer(argc: -4, exec: "/bin/x", padding: 1, args: ["a"])))
        XCTAssertNil(ProcessArgumentsParser.parse(buffer(argc: 100_000, exec: "/bin/x", padding: 1, args: ["a"])))
    }

    func testTruncatedBufferReturnsWhatIsThere() {
        let bytes = buffer(argc: 4, exec: "/bin/x", padding: 1, args: ["x", "y"])

        XCTAssertEqual(ProcessArgumentsParser.parse(bytes), ["x", "y"])
    }

    func testTooShortBufferIsNil() {
        XCTAssertNil(ProcessArgumentsParser.parse([1, 0]))
    }
}
