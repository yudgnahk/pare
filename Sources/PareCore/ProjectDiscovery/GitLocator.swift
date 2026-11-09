import Foundation

/// Finds Apple's git in a root-controlled developer directory. Never the `/usr/bin/git` shim, which opens
/// the "install developer tools" dialog without Command Line Tools, and never a user-writable install
/// such as Homebrew's, which other code running as the user could replace to borrow Pare's access.
public struct GitLocator: Sendable {
    static let commandLineToolsDirectory = "/Library/Developer/CommandLineTools"

    /// `xcode-select -p`, or nil when no developer directory is selected.
    public static let selectedDeveloperDirectory: @Sendable () async -> String? = {
        await ToolCommandRunner().capture(
            executable: URL(fileURLWithPath: "/usr/bin/xcode-select"),
            arguments: ["-p"]
        )
    }

    private let rootControlledPath: @Sendable (String) -> String?
    private let developerDirectory: @Sendable () async -> String?

    public init(
        rootControlledPath: @escaping @Sendable (String) -> String? = { RootControlledExecutable.resolve($0) },
        developerDirectory: @escaping @Sendable () async -> String? = GitLocator.selectedDeveloperDirectory
    ) {
        self.rootControlledPath = rootControlledPath
        self.developerDirectory = developerDirectory
    }

    /// Command Line Tools first (no launch needed), then the selected developer directory.
    public func locate() async -> URL? {
        if let git = rootControlledGit(in: Self.commandLineToolsDirectory) { return git }
        guard let developer = await developerDirectory(), !developer.isEmpty else { return nil }
        return rootControlledGit(in: developer)
    }

    private func rootControlledGit(in developerDirectory: String) -> URL? {
        let candidate = URL(fileURLWithPath: developerDirectory).appending(path: "usr/bin/git").path
        return rootControlledPath(candidate).map { URL(fileURLWithPath: $0) }
    }
}
