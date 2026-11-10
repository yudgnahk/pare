import XCTest
import PareCore
@testable import PareApp

/// A hung `brew cleanup` must never leave the sheet stuck on "Running…".
@MainActor
final class HomebrewCleanupModelTests: XCTestCase {

    func testStopAndTimeoutBothLeaveTheRunningPhase() async throws {
        let cases: [(name: String, timeout: TimeInterval, stop: Bool)] = [
            ("stopped by the user", BrewCleanupAction.defaultCleanupTimeoutSeconds, true),
            ("timed out", 0.2, false),
        ]
        for testCase in cases {
            let stuck = StuckBrewRunner()
            let runner = BrewRunner(brewPath: "/fake/bin/brew", processRunner: stuck)
            let model = HomebrewCleanupModel(action: BrewCleanupAction(runner: runner, cleanupTimeoutSeconds: testCase.timeout))

            model.startCleanUp()
            try await waitUntil { model.phase == .running }
            if testCase.stop { model.cancelCleanUp() }
            try await waitUntil { model.phase != .running }

            guard case .failed = model.phase else {
                return XCTFail("\(testCase.name): expected .failed, got \(model.phase)")
            }
        }
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<100 where !condition() {
            try await Task.sleep(nanoseconds: 50_000_000)
        }
    }
}

/// Previews one item, then streams `brew cleanup` output that never ends.
private final class StuckBrewRunner: ProcessRunning, @unchecked Sendable {
    private let lock = NSLock()
    private var open: [AsyncThrowingStream<ProcessOutputLine, Error>.Continuation] = []

    func run(executablePath: String, arguments: [String], environment: [String: String]?) async throws -> ProcessResult {
        ProcessResult(standardOutput: "Would remove: /opt/homebrew/Cellar/jq/1.6 (18 files, 1.1MB)\n",
                      standardError: "", exitCode: 0)
    }

    func streamLines(
        executablePath: String,
        arguments: [String],
        environment: [String: String]?
    ) -> AsyncThrowingStream<ProcessOutputLine, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(.stdout("==> Waiting for another brew process to finish"))
            lock.withLock { open.append(continuation) }
        }
    }
}
