import Foundation

/// Real `Foundation.Process` implementation of `ProcessRunning`.
///
/// Pipe draining uses DispatchQueue (OS-managed pthread pool) rather than Swift
/// cooperative threads so blocking reads never starve the concurrency runtime.
/// `terminationHandler` replaces `waitUntilExit()` for the same reason.
/// `standardInput = .nullDevice` prevents the child from inheriting the
/// terminal's stdin and becoming the foreground process group, which would
/// intercept keystrokes before macOS routes them to the GUI window.
public struct SystemProcessRunner: ProcessRunning {

    public init() {}

    // MARK: - Run to completion

    public func run(
        executablePath: String,
        arguments: [String],
        environment: [String: String]?
    ) async throws -> ProcessResult {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executablePath)
            process.arguments = arguments
            if let environment {
                process.environment = environment
            }
            process.standardInput = FileHandle.nullDevice

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
                return
            }

            // Drain both pipes on background OS threads (not the cooperative pool).
            let drainGroup = DispatchGroup()
            let stdoutBuffer = LockedDataBuffer()
            let stderrBuffer = LockedDataBuffer()

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
                continuation.resume(returning: ProcessResult(
                    standardOutput: String(data: stdoutBuffer.data, encoding: .utf8) ?? "",
                    standardError: String(data: stderrBuffer.data, encoding: .utf8) ?? "",
                    exitCode: proc.terminationStatus
                ))
            }
        }
    }

    // MARK: - Streaming

    public func streamLines(
        executablePath: String,
        arguments: [String],
        environment: [String: String]?
    ) -> AsyncThrowingStream<ProcessOutputLine, Error> {
        AsyncThrowingStream { continuation in
            Task {
                guard FileManager.default.fileExists(atPath: executablePath) else {
                    continuation.finish(throwing: ProcessRunnerError.executableNotFound(executablePath))
                    return
                }

                let process = Process()
                process.executableURL = URL(fileURLWithPath: executablePath)
                process.arguments = arguments
                if let environment {
                    process.environment = environment
                }
                process.standardInput = FileHandle.nullDevice

                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()
                process.standardOutput = stdoutPipe
                process.standardError = stderrPipe

                do { try process.run() } catch {
                    continuation.finish(throwing: error)
                    return
                }

                // Collect stderr text so a non-zero exit can report it even when
                // callers ignore the interleaved `.stderr` lines.
                let stderrBuffer = LockedTextBuffer()

                await withTaskGroup(of: Void.self) { group in
                    group.addTask {
                        do {
                            for try await line in stdoutPipe.fileHandleForReading.bytes.lines {
                                continuation.yield(.stdout(line))
                            }
                        } catch {}
                    }
                    group.addTask {
                        do {
                            for try await line in stderrPipe.fileHandleForReading.bytes.lines {
                                stderrBuffer.append(line + "\n")
                                continuation.yield(.stderr(line))
                            }
                        } catch {}
                    }
                }

                process.waitUntilExit()
                let status = process.terminationStatus
                if status != 0 {
                    let errText = stderrBuffer.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    continuation.finish(throwing: ProcessRunnerError.nonZeroExit(exitCode: status, stderr: errText))
                } else {
                    continuation.finish()
                }
            }
        }
    }
}

// MARK: - Locked buffers

/// Thread-safe byte buffer for draining subprocess pipes across DispatchQueue threads.
private final class LockedDataBuffer: @unchecked Sendable {
    private var _data = Data()
    private let lock = NSLock()

    func append(_ d: Data) {
        lock.withLock { _data.append(d) }
    }

    var data: Data {
        lock.withLock { _data }
    }
}

/// Thread-safe text buffer for collecting stderr across concurrent readers.
private final class LockedTextBuffer: @unchecked Sendable {
    private var _text = ""
    private let lock = NSLock()

    func append(_ s: String) {
        lock.withLock { _text += s }
    }

    var text: String {
        lock.withLock { _text }
    }
}
