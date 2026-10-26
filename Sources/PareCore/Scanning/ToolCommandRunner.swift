import Foundation

/// Short-timeout, null-stdin, bounded-output capture of a tool discovery command
/// (e.g. `uv cache dir`). Non-fatal by design: a missing executable, non-zero
/// exit, timeout, or garbage output all yield `nil` — never an error, never a
/// blocked scan. Shell startup files are never sourced.
public struct ToolCommandRunner: Sendable {
    /// Default timeout for discovery commands. They print one line; anything
    /// slower is treated as absent.
    public static let defaultTimeoutSeconds: TimeInterval = 3

    public let timeoutSeconds: TimeInterval

    public init(timeoutSeconds: TimeInterval = ToolCommandRunner.defaultTimeoutSeconds) {
        self.timeoutSeconds = timeoutSeconds
    }

    /// Resolves an executable name against `ToolSearchPath` for the given environment.
    /// Returns nil when not installed.
    public func resolveExecutable(named name: String, environmentVariables: [String: String]) -> URL? {
        guard !name.isEmpty, !name.contains("/") else { return nil }
        for directory in ToolSearchPath.directories(environment: environmentVariables) {
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
        let path = ToolSearchPath.pathValue(environment: environmentVariables)
        return await capture(executable: executable, arguments: command.arguments, environment: ["PATH": path])
    }

    /// Runs the executable with a bounded timeout and returns trimmed stdout on
    /// exit status 0. Any failure (launch error, non-zero exit, timeout) → nil.
    public func capture(executable: URL, arguments: [String], environment: [String: String] = [:]) async -> String? {
        guard let result = await run(executable: executable, arguments: arguments, environment: environment),
              result.exitCode == 0 else { return nil }
        return String(data: result.stdout, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Runs the executable with a bounded timeout and returns its exit code and raw stdout.
    /// `environment` is layered over the inherited one. Nil on launch failure, timeout or task
    /// cancellation, returned no later than the timeout even if the child or its children linger.
    public func run(
        executable: URL,
        arguments: [String],
        environment: [String: String] = [:]
    ) async -> (exitCode: Int32, stdout: Data)? {
        let merged = environment.isEmpty
            ? nil
            : ProcessInfo.processInfo.environment.merging(environment) { _, override in override }
        return await BoundedChildProcess.run(
            executable: executable,
            arguments: arguments,
            environment: merged,
            timeout: timeoutSeconds
        )
    }
}

