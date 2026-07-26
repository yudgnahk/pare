import Foundation

public enum BrewError: Error, LocalizedError {
    case notInstalled
    case failed(exitCode: Int32, stderr: String)

    public var errorDescription: String? {
        switch self {
        case .notInstalled:
            return "Homebrew is not installed. Install it from https://brew.sh"
        case .failed(let code, let stderr):
            return "brew exited with code \(code): \(stderr)"
        }
    }
}

/// Thin wrapper around the `brew` binary.
/// Detects the prefix, sets required env vars, and delegates subprocess
/// execution to an injected `ProcessRunning` (real `SystemProcessRunner`
/// by default; tests inject a stub).
public struct BrewRunner: Sendable {

    public static let shared = BrewRunner()

    public let brewPath: String?
    private let processRunner: any ProcessRunning

    public init(processRunner: any ProcessRunning = SystemProcessRunner()) {
        let detected: String?
        if FileManager.default.fileExists(atPath: "/opt/homebrew/bin/brew") {
            detected = "/opt/homebrew/bin/brew"
        } else if FileManager.default.fileExists(atPath: "/usr/local/bin/brew") {
            detected = "/usr/local/bin/brew"
        } else {
            detected = nil
        }
        self.init(brewPath: detected, processRunner: processRunner)
    }

    /// Test seam: explicit brew path (`nil` = treated as not installed) plus an
    /// injected process runner.
    public init(brewPath: String?, processRunner: any ProcessRunning = SystemProcessRunner()) {
        self.brewPath = brewPath
        self.processRunner = processRunner
    }

    public var isInstalled: Bool { brewPath != nil }

    /// Runs a brew subcommand and returns combined stdout output.
    /// Throws `BrewError.notInstalled` or `BrewError.failed` on non-zero exit.
    public func run(_ args: [String]) async throws -> String {
        guard let brewPath else { throw BrewError.notInstalled }

        let result = try await processRunner.run(
            executablePath: brewPath,
            arguments: args,
            environment: makeEnvironment()
        )
        guard result.exitCode == 0 else {
            throw BrewError.failed(exitCode: result.exitCode, stderr: result.standardError)
        }
        return result.standardOutput
    }

    /// Runs a brew subcommand and streams output lines as they arrive.
    /// Yields both stdout and stderr lines interleaved.
    public func stream(_ args: [String]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                guard let brewPath else {
                    continuation.finish(throwing: BrewError.notInstalled)
                    return
                }

                do {
                    let lines = processRunner.streamLines(
                        executablePath: brewPath,
                        arguments: args,
                        environment: makeEnvironment()
                    )
                    for try await line in lines {
                        continuation.yield(line.text)
                    }
                    continuation.finish()
                } catch let error as ProcessRunnerError {
                    switch error {
                    case .nonZeroExit(let code, _):
                        // stderr lines were already yielded inline; keep the
                        // historical empty-stderr error shape.
                        continuation.finish(throwing: BrewError.failed(exitCode: code, stderr: ""))
                    case .executableNotFound:
                        continuation.finish(throwing: BrewError.notInstalled)
                    }
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Private

    private func makeEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["HOMEBREW_NO_AUTO_UPDATE"] = "1"
        env["HOME"] = FileManager.default.homeDirectoryForCurrentUser.path
        return env
    }
}
