import Foundation

/// Finds a real git binary without ever launching the `/usr/bin/git` shim, which opens
/// the "install developer tools" dialog on machines without Command Line Tools.
public struct GitLocator: Sendable {
    static let shimDirectory = "/usr/bin"

    /// `xcode-select -p`, or nil when no developer directory is selected.
    public static let selectedDeveloperDirectory: @Sendable () async -> String? = {
        await ToolCommandRunner().capture(
            executable: URL(fileURLWithPath: "/usr/bin/xcode-select"),
            arguments: ["-p"]
        )
    }

    private let environment: [String: String]
    private let isExecutable: @Sendable (String) -> Bool
    private let developerDirectory: @Sendable () async -> String?

    public init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        isExecutable: @escaping @Sendable (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) },
        developerDirectory: @escaping @Sendable () async -> String? = GitLocator.selectedDeveloperDirectory
    ) {
        self.environment = environment
        self.isExecutable = isExecutable
        self.developerDirectory = developerDirectory
    }

    /// `ToolSearchPath` (minus `/usr/bin`), then the selected developer directory.
    public func locate() async -> URL? {
        for directory in ToolSearchPath.directories(environment: environment) where directory != Self.shimDirectory {
            let candidate = directory + "/git"
            if isExecutable(candidate) { return URL(fileURLWithPath: candidate) }
        }
        guard let developer = await developerDirectory(), !developer.isEmpty else { return nil }
        let candidate = URL(fileURLWithPath: developer).appending(path: "usr/bin/git").path
        return isExecutable(candidate) ? URL(fileURLWithPath: candidate) : nil
    }
}
