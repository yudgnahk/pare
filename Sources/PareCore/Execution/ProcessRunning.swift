import Foundation

// MARK: - ProcessResult

/// Captured output of a completed subprocess run.
public struct ProcessResult: Sendable, Equatable {
    public let standardOutput: String
    public let standardError: String
    public let exitCode: Int32

    public init(standardOutput: String, standardError: String, exitCode: Int32) {
        self.standardOutput = standardOutput
        self.standardError = standardError
        self.exitCode = exitCode
    }
}

// MARK: - ProcessOutputLine

/// One line of live subprocess output, tagged by originating stream.
public enum ProcessOutputLine: Sendable, Equatable {
    case stdout(String)
    case stderr(String)

    /// The line text regardless of stream.
    public var text: String {
        switch self {
        case .stdout(let line), .stderr(let line):
            return line
        }
    }
}

// MARK: - ProcessRunnerError

public enum ProcessRunnerError: Error, LocalizedError, Sendable {
    /// The executable does not exist on disk.
    case executableNotFound(String)
    /// The process exited non-zero (streaming API only — `run` reports the
    /// exit code through `ProcessResult` and never throws for non-zero exits).
    case nonZeroExit(exitCode: Int32, stderr: String)

    public var errorDescription: String? {
        switch self {
        case .executableNotFound(let path):
            return "Executable not found: \(path)"
        case .nonZeroExit(let code, let stderr):
            return stderr.isEmpty
                ? "Process exited with code \(code)"
                : "Process exited with code \(code): \(stderr)"
        }
    }
}

// MARK: - ProcessRunning

/// Injection seam for subprocess execution.
///
/// Production code uses `SystemProcessRunner` (the real `Foundation.Process`
/// implementation). Tests substitute a stub so `BrewRunner`, `MaintenanceRunner`,
/// and `BrewOutdatedChecker` can be exercised without spawning real processes.
public protocol ProcessRunning: Sendable {
    /// Runs the executable to completion and returns captured stdout/stderr plus
    /// the exit code. Throws only when the process cannot be launched; non-zero
    /// exits are reported via `ProcessResult.exitCode`.
    func run(
        executablePath: String,
        arguments: [String],
        environment: [String: String]?
    ) async throws -> ProcessResult

    /// Streams output lines as they arrive, tagged by stream. Finishes throwing
    /// `ProcessRunnerError.nonZeroExit` (with collected stderr) when the process
    /// exits non-zero, or `ProcessRunnerError.executableNotFound` when the
    /// executable is missing.
    func streamLines(
        executablePath: String,
        arguments: [String],
        environment: [String: String]?
    ) -> AsyncThrowingStream<ProcessOutputLine, Error>
}
