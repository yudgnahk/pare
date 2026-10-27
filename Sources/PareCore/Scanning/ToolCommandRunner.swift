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

    /// Runs a confirmed, unchanged third-party tool with a sanitized environment and returns trimmed stdout;
    /// nil when the tool is unconfirmed or changed (treated as absent) or the command fails.
    public func captureConfirmed(
        _ tool: ConfirmableTool,
        arguments: [String],
        registry: ConfirmedToolRegistry = .shared,
        environment: [String: String] = [:],
        baseEnvironment: [String: String] = ProcessInfo.processInfo.environment
    ) async -> String? {
        guard let executable = await registry.launchURL(for: tool) else { return nil }
        let merged = baseEnvironment.merging(environment) { _, override in override }
        guard let result = await BoundedChildProcess.run(
            executable: executable,
            arguments: arguments,
            environment: ToolSpawnEnvironment.sanitized(merged),
            timeout: timeoutSeconds
        ), result.exitCode == 0 else { return nil }
        return String(data: result.stdout, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
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

