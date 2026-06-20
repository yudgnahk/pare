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

/// Thin process wrapper around the `brew` binary.
/// Detects the prefix, sets required env vars, and reads stdout + stderr
/// concurrently to prevent pipe deadlock.
public struct BrewRunner: Sendable {

    public static let shared = BrewRunner()

    public let brewPath: String?

    public init() {
        if FileManager.default.fileExists(atPath: "/opt/homebrew/bin/brew") {
            brewPath = "/opt/homebrew/bin/brew"
        } else if FileManager.default.fileExists(atPath: "/usr/local/bin/brew") {
            brewPath = "/usr/local/bin/brew"
        } else {
            brewPath = nil
        }
    }

    public var isInstalled: Bool { brewPath != nil }

    /// Runs a brew subcommand and returns combined stdout output.
    /// Throws `BrewError.notInstalled` or `BrewError.failed` on non-zero exit.
    public func run(_ args: [String]) async throws -> String {
        guard let brewPath else { throw BrewError.notInstalled }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: brewPath)
        process.arguments = args
        process.environment = makeEnvironment()

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()

        // Read stdout and stderr concurrently to prevent pipe deadlock.
        var stdoutData = Data()
        var stderrData = Data()

        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            }
            group.addTask {
                stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            }
        }

        process.waitUntilExit()

        let status = process.terminationStatus
        let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
        guard status == 0 else {
            let stderr = String(data: stderrData, encoding: .utf8) ?? ""
            throw BrewError.failed(exitCode: status, stderr: stderr)
        }
        return stdout
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

                let process = Process()
                process.executableURL = URL(fileURLWithPath: brewPath)
                process.arguments = args
                process.environment = makeEnvironment()

                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()
                process.standardOutput = stdoutPipe
                process.standardError = stderrPipe

                do { try process.run() } catch {
                    continuation.finish(throwing: error)
                    return
                }

                await withTaskGroup(of: Void.self) { group in
                    group.addTask {
                        do {
                            for try await line in stdoutPipe.fileHandleForReading.bytes.lines {
                                continuation.yield(line)
                            }
                        } catch {}
                    }
                    group.addTask {
                        do {
                            for try await line in stderrPipe.fileHandleForReading.bytes.lines {
                                continuation.yield(line)
                            }
                        } catch {}
                    }
                }

                process.waitUntilExit()

                let status = process.terminationStatus
                if status != 0 {
                    continuation.finish(throwing: BrewError.failed(exitCode: status, stderr: ""))
                } else {
                    continuation.finish()
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
