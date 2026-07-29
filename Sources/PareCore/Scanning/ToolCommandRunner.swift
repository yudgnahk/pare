import Foundation

/// Short-timeout, null-stdin, bounded-output capture of a tool discovery command
/// (e.g. `uv cache dir`). Non-fatal by design: a missing executable, non-zero
/// exit, timeout, or garbage output all yield `nil` — never an error, never a
/// blocked scan. Shell startup files are never sourced.
public struct ToolCommandRunner: Sendable {
    /// Default timeout for discovery commands. They print one line; anything
    /// slower is treated as absent.
    public static let defaultTimeoutSeconds: TimeInterval = 3

    /// Conventional install locations checked in addition to PATH — Finder-launched
    /// GUI apps do not inherit the user's shell PATH.
    public static let conventionalSearchPaths = [
        "/opt/homebrew/bin",
        "/usr/local/bin",
    ]

    public let timeoutSeconds: TimeInterval

    public init(timeoutSeconds: TimeInterval = ToolCommandRunner.defaultTimeoutSeconds) {
        self.timeoutSeconds = timeoutSeconds
    }

    /// Resolves an executable name against the given environment's PATH entries
    /// plus conventional Homebrew locations. Returns nil when not installed.
    public func resolveExecutable(named name: String, environmentVariables: [String: String]) -> URL? {
        guard !name.isEmpty, !name.contains("/") else { return nil }
        let pathEntries = (environmentVariables["PATH"] ?? "")
            .split(separator: ":")
            .map(String.init)
        var searched = Set<String>()
        for directory in pathEntries + Self.conventionalSearchPaths {
            guard !directory.isEmpty, searched.insert(directory).inserted else { continue }
            let candidate = URL(fileURLWithPath: directory).appending(path: name)
            if FileManager.default.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }

    /// Runs a descriptor's native discovery command and returns trimmed stdout,
    /// or nil when the tool is absent or the command fails/times out.
    public func captureOutput(
        of command: ToolCacheCommand,
        environmentVariables: [String: String]
    ) async -> String? {
        guard let executable = resolveExecutable(
            named: command.executableName,
            environmentVariables: environmentVariables
        ) else { return nil }
        return await capture(executable: executable, arguments: command.arguments)
    }

    /// Runs the executable with a bounded timeout and returns trimmed stdout on
    /// exit status 0. Any failure (launch error, non-zero exit, timeout) → nil.
    public func capture(executable: URL, arguments: [String]) async -> String? {
        let timeout = timeoutSeconds
        return await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = executable
            process.arguments = arguments
            process.standardInput = FileHandle.nullDevice

            let stdoutPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = FileHandle.nullDevice

            do {
                try process.run()
            } catch {
                continuation.resume(returning: nil)
                return
            }

            // Drain stdout on an OS-managed thread (not the cooperative pool)
            // so a blocking read can never starve the concurrency runtime.
            let drainGroup = DispatchGroup()
            let buffer = LockedOutputBuffer()
            drainGroup.enter()
            DispatchQueue.global(qos: .utility).async {
                buffer.append(stdoutPipe.fileHandleForReading.readDataToEndOfFile())
                drainGroup.leave()
            }

            let timedOut = LockedFlag()
            process.terminationHandler = { proc in
                drainGroup.wait()
                guard proc.terminationStatus == 0, !timedOut.value else {
                    continuation.resume(returning: nil)
                    return
                }
                let output = String(data: buffer.data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                continuation.resume(returning: output)
            }

            // Timeout: terminate the process; terminationHandler resolves nil.
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout) {
                if process.isRunning {
                    timedOut.value = true
                    process.terminate()
                }
            }
        }
    }
}

// MARK: - Locked helpers

private final class LockedOutputBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = Data()

    func append(_ data: Data) {
        lock.lock()
        defer { lock.unlock() }
        storage.append(data)
    }

    var data: Data {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}

private final class LockedFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = false

    var value: Bool {
        get {
            lock.lock()
            defer { lock.unlock() }
            return storage
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            storage = newValue
        }
    }
}
