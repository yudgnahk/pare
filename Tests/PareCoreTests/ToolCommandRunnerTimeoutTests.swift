import XCTest
@testable import PareCore

final class ToolCommandRunnerTimeoutTests: XCTestCase {
    private let timeout: TimeInterval = 0.5
    /// Timeout plus SIGKILL grace plus CI scheduling slack; far below the children's 30 s sleep.
    private let bound: TimeInterval = 4
    private var pidFile: URL!

    override func setUp() {
        pidFile = FileManager.default.temporaryDirectory.appending(path: "pare-runner-pid-\(UUID().uuidString)")
    }

    override func tearDown() {
        if let pid = recordedPID() { kill(pid, SIGKILL) }
        try? FileManager.default.removeItem(at: pidFile)
    }

    private func shell(_ script: String) async -> (result: (exitCode: Int32, stdout: Data)?, elapsed: TimeInterval) {
        let started = Date()
        let result = await ToolCommandRunner(timeoutSeconds: timeout).run(
            executable: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", script]
        )
        return (result, Date().timeIntervalSince(started))
    }

    private func recordedPID() -> pid_t? {
        (try? String(contentsOf: pidFile, encoding: .utf8))
            .flatMap { pid_t($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
    }

    /// Polls until the process is gone, for at most the SIGKILL grace plus slack.
    private func waitUntilGone(_ pid: pid_t) async -> Bool {
        for _ in 0..<40 {
            if kill(pid, 0) == -1, errno == ESRCH { return true }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        return false
    }

    func testChildIgnoringSigtermReturnsNilAndIsKilled() async throws {
        let (result, elapsed) = await shell("echo $$ > '\(pidFile.path)'; trap '' TERM; while :; do sleep 1; done")

        XCTAssertNil(result)
        XCTAssertLessThan(elapsed, bound)
        let pid = try XCTUnwrap(recordedPID())
        let gone = await waitUntilGone(pid)
        XCTAssertTrue(gone, "SIGKILL after the grace period must end a child that ignores SIGTERM")
    }

    func testGrandchildHoldingStdoutDoesNotHangTheRunner() async throws {
        let (result, elapsed) = await shell("sleep 30 & echo $! > '\(pidFile.path)'; exit 0")

        XCTAssertNil(result, "no EOF before the deadline is a timeout, even though the direct child exited 0")
        XCTAssertLessThan(elapsed, bound)
        let pid = try XCTUnwrap(recordedPID())
        let gone = await waitUntilGone(pid)
        XCTAssertTrue(gone, "the grandchild shares the child's process group and must be killed with it")
    }

    func testCancellationReturnsNilBeforeTheTimeout() async {
        let started = Date()
        let task = Task {
            await ToolCommandRunner(timeoutSeconds: 30).run(
                executable: URL(fileURLWithPath: "/bin/sleep"),
                arguments: ["30"]
            )
        }
        try? await Task.sleep(nanoseconds: 200_000_000)
        task.cancel()

        let result = await task.value

        XCTAssertNil(result)
        XCTAssertLessThan(Date().timeIntervalSince(started), bound)
    }

    func testOutputLargerThanThePipeBufferIsCapturedWhole() async {
        let result = await ToolCommandRunner().run(
            executable: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "head -c 1000000 /dev/zero"]
        )

        XCTAssertEqual(result?.exitCode, 0)
        XCTAssertEqual(result?.stdout.count, 1_000_000)
    }

    func testSignalledChildReportsTheSignalNumber() async {
        let result = await ToolCommandRunner().run(
            executable: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "kill -KILL $$"]
        )

        XCTAssertEqual(result?.exitCode, SIGKILL)
    }
}
