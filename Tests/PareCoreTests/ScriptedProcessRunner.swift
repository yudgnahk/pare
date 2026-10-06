import Foundation
@testable import PareCore

/// `ProcessRunning` stub that answers each call from a script and records every invocation.
final class ScriptedProcessRunner: ProcessRunning, @unchecked Sendable {
    struct Invocation: Equatable {
        let executablePath: String
        let arguments: [String]
    }

    typealias Script = @Sendable (Invocation) throws -> ProcessResult

    private let script: Script
    private let lock = NSLock()
    private var recorded: [Invocation] = []

    init(script: @escaping Script) {
        self.script = script
    }

    var invocations: [Invocation] { lock.withLock { recorded } }

    func run(
        executablePath: String,
        arguments: [String],
        environment: [String: String]?
    ) async throws -> ProcessResult {
        let invocation = Invocation(executablePath: executablePath, arguments: arguments)
        lock.withLock { recorded.append(invocation) }
        return try script(invocation)
    }

    func streamLines(
        executablePath: String,
        arguments: [String],
        environment: [String: String]?
    ) -> AsyncThrowingStream<ProcessOutputLine, Error> {
        let invocation = Invocation(executablePath: executablePath, arguments: arguments)
        lock.withLock { recorded.append(invocation) }
        let script = script
        return AsyncThrowingStream { continuation in
            do {
                let result = try script(invocation)
                for line in result.standardOutput.split(separator: "\n") {
                    continuation.yield(.stdout(String(line)))
                }
                if result.exitCode == 0 {
                    continuation.finish()
                } else {
                    continuation.finish(throwing: ProcessRunnerError.nonZeroExit(
                        exitCode: result.exitCode, stderr: result.standardError
                    ))
                }
            } catch {
                continuation.finish(throwing: error)
            }
        }
    }
}

extension ProcessResult {
    static func ok(_ stdout: String = "") -> ProcessResult {
        ProcessResult(standardOutput: stdout, standardError: "", exitCode: 0)
    }

    static func failure(_ stderr: String, exitCode: Int32 = 1) -> ProcessResult {
        ProcessResult(standardOutput: "", standardError: stderr, exitCode: exitCode)
    }
}
