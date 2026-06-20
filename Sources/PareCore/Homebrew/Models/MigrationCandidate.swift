import Foundation

/// An app installed outside Homebrew that has a matching cask and can be adopted.
public struct MigrationCandidate: Identifiable, Sendable {
    public let id: String
    public let caskToken: String
    public let appName: String
    public let bundleID: String?
    public let currentPath: String

    /// The recommended command to adopt this app under Homebrew management.
    public var adoptCommand: String { "brew install --cask --adopt \(caskToken)" }

    public init(
        caskToken: String,
        appName: String,
        bundleID: String?,
        currentPath: String
    ) {
        self.id = caskToken
        self.caskToken = caskToken
        self.appName = appName
        self.bundleID = bundleID
        self.currentPath = currentPath
    }
}
