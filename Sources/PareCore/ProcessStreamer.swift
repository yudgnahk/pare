import Foundation

/// Streams a subprocess's output lines as they arrive.
///
/// Shared by `BrewRunner.stream` and `MaintenanceRunner` so the pipe-draining
/// and termination handling exist once. Exit status is delivered through the
/// non-blocking `terminationHandler` pattern (see `BrewRunner.run`) —
/// `waitUntilExit()` would block a cooperative-pool thread and can starve the
/// Swift concurrency runtime.
public enum ProcessStreamer {
    /// Runs `executable` with `arguments`, yielding stdout lines as they arrive.
    ///
    /// stderr lines are always captured for the exit error and are additionally
    /// yielded interleaved when `yieldsStderr` is true. On non-zero exit the
    /// stream finishes by throwing `makeExitError(exitCode, capturedStderr)`.
    public static func stream(
        executable: URL,
        arguments: [String],
        environment: [String: String]? = nil,
        yieldsStderr: Bool,
        makeExitError: @escaping @Sendable (_ exitCode: Int32, _ stderr: String) -> Error
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let process = Process()
            process.executableURL = executable
            process.arguments = arguments
            if let environment {
                process.environment = environment
            }
            process.standardInput = FileHandle.nullDevice

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            // Termination status arrives via handler (never waitUntilExit) and is
            // awaited after both pipes hit EOF.
            let (statusStream, statusContinuation) = AsyncStream.makeStream(of: Int32.self)
            process.terminationHandler = { proc in
                statusContinuation.yield(proc.terminationStatus)
                statusContinuation.finish()
            }

            do {
                try process.run()
            } catch {
                statusContinuation.finish()
                continuation.finish(throwing: error)
                return
            }

            Task {
                let stderrBuffer = LockedBuffer()

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
                                if yieldsStderr {
                                    continuation.yield(line)
                                }
                                stderrBuffer.append(line + "\n")
                            }
                        } catch {}
                    }
                }

                var status: Int32 = 0
                for await value in statusStream {
                    status = value
                }

                if status != 0 {
                    let stderr = stderrBuffer.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    continuation.finish(throwing: makeExitError(status, stderr))
                } else {
                    continuation.finish()
                }
            }
        }
    }
}

/// Thread-safe buffer for collecting subprocess output across threads.
/// The single shared copy — `BrewRunner` and `ProcessStreamer` both drain into it.
final class LockedBuffer: @unchecked Sendable {
    private var _data = Data()
    private let lock = NSLock()

    func append(_ data: Data) {
        lock.withLock { _data.append(data) }
    }

    func append(_ text: String) {
        append(Data(text.utf8))
    }

    var data: Data {
        lock.withLock { _data }
    }

    var text: String {
        String(data: data, encoding: .utf8) ?? ""
    }
}
