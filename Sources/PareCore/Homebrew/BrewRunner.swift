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
    ///
    /// Pipe draining uses DispatchQueue (OS-managed pthread pool) rather than
    /// Swift cooperative threads so blocking reads never starve the concurrency
    /// runtime. `terminationHandler` replaces `waitUntilExit()` for the same
    /// reason. `standardInput = .nullDevice` prevents brew from inheriting the
    /// terminal's stdin and becoming the foreground process group, which would
    /// intercept keystrokes before macOS routes them to the GUI window.
    public func run(_ args: [String]) async throws -> String {
        guard let brewPath else { throw BrewError.notInstalled }

        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: brewPath)
            process.arguments = args
            process.environment = makeEnvironment()
            process.standardInput = FileHandle.nullDevice

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            // Drain both pipes on background OS threads (not cooperative pool).
            let drainGroup = DispatchGroup()
            let stdoutBuffer = LockedBuffer()
            let stderrBuffer = LockedBuffer()

            drainGroup.enter()
            DispatchQueue.global(qos: .utility).async {
                stdoutBuffer.append(stdoutPipe.fileHandleForReading.readDataToEndOfFile())
                drainGroup.leave()
            }

            drainGroup.enter()
            DispatchQueue.global(qos: .utility).async {
                stderrBuffer.append(stderrPipe.fileHandleForReading.readDataToEndOfFile())
                drainGroup.leave()
            }

            process.terminationHandler = { proc in
                drainGroup.wait()
                let stdout = String(data: stdoutBuffer.data, encoding: .utf8) ?? ""
                if proc.terminationStatus == 0 {
                    continuation.resume(returning: stdout)
                } else {
                    let stderr = String(data: stderrBuffer.data, encoding: .utf8) ?? ""
                    continuation.resume(throwing: BrewError.failed(exitCode: proc.terminationStatus, stderr: stderr))
                }
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    /// Runs a brew subcommand that requires admin privileges.
    ///
    /// Brew must run as the current user — it cannot run as root. It calls
    /// `/usr/bin/sudo` internally for privileged steps (pkgutil, system deletes).
    /// We inject the password by placing a temporary `sudo` wrapper first on PATH;
    /// the wrapper pipes the password to `sudo -S` so the user is never prompted.
    /// The temp directory is deleted the moment the stream finishes.
    public func streamPrivileged(_ args: [String], password: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            do {
                let tempDir = try createSudoWrapper(password: password)
                Task {
                    defer { try? FileManager.default.removeItem(atPath: tempDir) }
                    guard let brewPath else {
                        continuation.finish(throwing: BrewError.notInstalled)
                        return
                    }

                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: brewPath)
                    process.arguments = args
                    process.standardInput = FileHandle.nullDevice

                    var env = makeEnvironment()
                    env["PATH"] = "\(tempDir):" + (env["PATH"] ?? "/usr/local/bin:/usr/bin:/bin")
                    process.environment = env

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
                    if process.terminationStatus != 0 {
                        continuation.finish(throwing: BrewError.failed(exitCode: process.terminationStatus, stderr: ""))
                    } else {
                        continuation.finish()
                    }
                }
            } catch {
                continuation.finish(throwing: error)
            }
        }
    }

    private func createSudoWrapper(password: String) throws -> String {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("pare-sudo-\(UUID().uuidString)")
            .path
        try FileManager.default.createDirectory(atPath: tempDir, withIntermediateDirectories: true, attributes: nil)

        let wrapperPath = "\(tempDir)/sudo"
        // Single-quote the password to handle most special chars.
        // A literal ' becomes '\'' (end quote, escaped quote, reopen quote).
        let escaped = password.replacingOccurrences(of: "'", with: "'\\''")
        let script = "#!/bin/sh\nprintf '%s\\n' '\(escaped)' | /usr/bin/sudo -S \"$@\"\n"
        try script.write(toFile: wrapperPath, atomically: true, encoding: .utf8)
        // 700: only this process can read/execute — minimise the exposure window.
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: 0o700)],
            ofItemAtPath: wrapperPath
        )
        return tempDir
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
                process.standardInput = FileHandle.nullDevice

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

// Thread-safe buffer for draining subprocess pipes across DispatchQueue threads.
private final class LockedBuffer: @unchecked Sendable {
    private var _data = Data()
    private let lock = NSLock()

    func append(_ d: Data) {
        lock.withLock { _data.append(d) }
    }

    var data: Data {
        lock.withLock { _data }
    }
}
