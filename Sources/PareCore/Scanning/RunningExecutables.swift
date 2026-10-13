import Foundation

/// Absolute paths of executables running right now; nil when the snapshot is unavailable.
public protocol RunningExecutablesProviding: Sendable {
    func runningExecutablePaths() async -> [String]?
}

/// One bounded `ps -axo comm=` run; on macOS `comm` is the executable's full path.
public struct PsRunningExecutablesProvider: RunningExecutablesProviding {
    static let psPath = "/bin/ps"
    public static let defaultTimeoutSeconds: TimeInterval = 5

    private let runner: ToolCommandRunner
    private let executable: URL

    public init(timeoutSeconds: TimeInterval = PsRunningExecutablesProvider.defaultTimeoutSeconds) {
        self.init(executable: URL(fileURLWithPath: Self.psPath), timeoutSeconds: timeoutSeconds)
    }

    /// Tests point `executable` at a script that prints, fails or times out.
    init(executable: URL, timeoutSeconds: TimeInterval) {
        self.executable = executable
        runner = ToolCommandRunner(timeoutSeconds: timeoutSeconds)
    }

    public func runningExecutablePaths() async -> [String]? {
        guard let output = await runner.capture(executable: executable, arguments: ["-axo", "comm="]) else { return nil }
        let paths = output.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasPrefix("/") }
        // No absolute path at all is not a real process list; treat it as unavailable.
        return paths.isEmpty ? nil : paths
    }
}
