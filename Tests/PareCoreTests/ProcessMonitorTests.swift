import XCTest
@testable import PareCore

final class ProcessMonitorTests: XCTestCase {

    private let secretToken = "tok_9f8e7d6c5b4a3210secret"
    private let agentID = UUID()
    private var agentsDirectory: URL!

    override func setUpWithError() throws {
        agentsDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("pare_monitor_\(UUID().uuidString)", isDirectory: true)
        let folder = agentsDirectory.appendingPathComponent("Users-u-Projects-shop", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let json = #"{"title":"Fix checkout","cwd":"/Users/u/Projects/shop","lastStatus":"running"}"#
        try Data(json.utf8).write(to: folder.appendingPathComponent(agentID.uuidString.lowercased() + ".json"))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: agentsDirectory)
    }

    private var claudeArguments: [String] {
        [
            "/opt/homebrew/bin/claude",
            "--mcp-config",
            #"{"mcpServers":{"paseo":{"url":"http://127.0.0.1:6767/mcp/agents?callerAgentId=\#(agentID.uuidString.lowercased())&auth=\#(secretToken)"}}}"#,
            "--append-system-prompt",
            "internal instructions \(secretToken)"
        ]
    }

    private func records(cpu: UInt64) -> [ProcessRecord] {
        [
            ProcessRecord(id: ProcessID(pid: 10, startMicros: 1), parentPID: 1, kernelName: "Paseo Helper",
                          executablePath: "/Applications/Paseo.app/Contents/MacOS/Paseo Helper", footprintBytes: 100 << 20, cpuTimeNanos: 0),
            ProcessRecord(id: ProcessID(pid: 20, startMicros: 1), parentPID: 10, kernelName: "claude",
                          executablePath: "/opt/homebrew/bin/claude", footprintBytes: 250 << 20, cpuTimeNanos: cpu),
            ProcessRecord(id: ProcessID(pid: 30, startMicros: 1), parentPID: 20, kernelName: "node",
                          executablePath: "/usr/local/bin/node", footprintBytes: 40 << 20, cpuTimeNanos: 0)
        ]
    }

    private func makeMonitor(provider: FakeProcessProvider, clock: FakeMonotonicClock = FakeMonotonicClock()) -> ProcessMonitor {
        ProcessMonitor(
            provider: provider,
            paseo: PaseoAgentResolver(agentsDirectory: agentsDirectory),
            monotonicNanos: { clock.next() }
        )
    }

    private func fakeProvider(cpu: UInt64 = 0) -> FakeProcessProvider {
        FakeProcessProvider(records: records(cpu: cpu), arguments: [
            10: ["Paseo Daemon"],
            20: claudeArguments,
            30: ["node", "/u/bin/gitnexus", "mcp", "--token=\(secretToken)"]
        ])
    }

    func testTreeNamesProcessesAndAttachesPaseoSession() async throws {
        let tree = try await makeMonitor(provider: fakeProvider()).refresh()

        let daemon = try XCTUnwrap(tree.roots.first)
        XCTAssertEqual(daemon.name, "Paseo Daemon")
        let claude = try XCTUnwrap(daemon.children.first)
        XCTAssertEqual(claude.name, "Claude Code")
        XCTAssertEqual(claude.paseoAgent?.title, "Fix checkout")
        XCTAssertEqual(claude.paseoAgent?.lastStatus, "running")
        XCTAssertEqual(claude.children.first?.name, "gitnexus mcp")
        XCTAssertEqual(daemon.branchFootprintBytes, 390 << 20)
    }

    func testModelNeverContainsRawArguments() async throws {
        let tree = try await makeMonitor(provider: fakeProvider()).refresh()

        var dumped = ""
        dump(tree, to: &dumped)
        let rendered = dumped + String(reflecting: tree)
        for fragment in [secretToken, "--mcp-config", "127.0.0.1:6767", "callerAgentId", agentID.uuidString.lowercased(), "internal instructions"] {
            XCTAssertFalse(rendered.localizedCaseInsensitiveContains(fragment), "model leaks \(fragment)")
        }
    }

    func testArgumentsAreReadOncePerProcessLifetime() async throws {
        let provider = fakeProvider()
        let monitor = makeMonitor(provider: provider)

        _ = try await monitor.refresh()
        _ = try await monitor.refresh()

        XCTAssertEqual(provider.argumentReads, [10: 1, 20: 1, 30: 1])
    }

    func testCPUAppearsFromTheSecondSample() async throws {
        let provider = fakeProvider(cpu: 0)
        let clock = FakeMonotonicClock(step: 2_000_000_000)
        let monitor = makeMonitor(provider: provider, clock: clock)

        let first = try await monitor.refresh()
        XCTAssertNil(first.totalCPUPercent)

        provider.records = records(cpu: 1_000_000_000)
        let second = try await monitor.refresh()
        XCTAssertEqual(second.totalCPUPercent ?? -1, 50, accuracy: 0.0001)
    }

    func testStaleBaselineIsNotUsedForCPU() async throws {
        let provider = fakeProvider(cpu: 0)
        let clock = FakeMonotonicClock(step: ProcessMonitor.maxBaselineAgeNanos + 1)
        let monitor = makeMonitor(provider: provider, clock: clock)

        _ = try await monitor.refresh()
        provider.records = records(cpu: 1_000_000_000)
        let second = try await monitor.refresh()

        XCTAssertNil(second.totalCPUPercent)
    }

    func testListingFailurePropagates() async {
        let provider = fakeProvider()
        provider.failure = ProcessSnapshotError.listingFailed(errno: EPERM)

        do {
            _ = try await makeMonitor(provider: provider).refresh()
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? ProcessSnapshotError, .listingFailed(errno: EPERM))
        }
    }

    func testWithoutPaseoDirectoryAgentsShowAsPlainProcesses() async throws {
        let monitor = ProcessMonitor(
            provider: fakeProvider(),
            paseo: PaseoAgentResolver(agentsDirectory: agentsDirectory.appendingPathComponent("missing")),
            monotonicNanos: { 1 }
        )

        let claude = try await monitor.refresh().roots.first?.children.first

        XCTAssertEqual(claude?.name, "Claude Code")
        XCTAssertNil(claude?.paseoAgent)
    }
}

/// Provider serving canned records and argv, counting argv reads.
final class FakeProcessProvider: ProcessSnapshotProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var storedRecords: [ProcessRecord]
    private let storedArguments: [Int32: [String]]
    private var reads: [Int32: Int] = [:]
    private var storedFailure: Error?

    init(records: [ProcessRecord], arguments: [Int32: [String]]) {
        self.storedRecords = records
        self.storedArguments = arguments
    }

    var records: [ProcessRecord] {
        get { lock.lock(); defer { lock.unlock() }; return storedRecords }
        set { lock.lock(); storedRecords = newValue; lock.unlock() }
    }

    var failure: Error? {
        get { lock.lock(); defer { lock.unlock() }; return storedFailure }
        set { lock.lock(); storedFailure = newValue; lock.unlock() }
    }

    var argumentReads: [Int32: Int] {
        lock.lock(); defer { lock.unlock() }
        return reads
    }

    func listProcesses() throws -> [ProcessRecord] {
        if let failure { throw failure }
        return records
    }

    func arguments(of pid: Int32) -> [String]? {
        lock.lock(); defer { lock.unlock() }
        reads[pid, default: 0] += 1
        return storedArguments[pid]
    }
}

/// Monotonic clock advancing a fixed step per reading.
final class FakeMonotonicClock: @unchecked Sendable {
    private let lock = NSLock()
    private let step: UInt64
    private var value: UInt64 = 1_000

    init(step: UInt64 = 1_000_000_000) {
        self.step = step
    }

    func next() -> UInt64 {
        lock.lock(); defer { lock.unlock() }
        value += step
        return value
    }
}
