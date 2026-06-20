import Foundation

public struct BrewCask: Identifiable, Sendable {
    public let id: String
    public let token: String
    public let version: String
    public let autoUpdates: Bool
    public let installedAppNames: [String]
    public let installDate: Date?
    /// True when Homebrew records the cask as installed but none of its .app
    /// bundles are found in the standard application directories.  This happens
    /// when the app was removed manually (Trash / third-party uninstaller)
    /// without running `brew uninstall --cask`.
    public let isOrphaned: Bool
    /// True for pkg-based casks (e.g. Microsoft Teams, TeamViewer) whose
    /// uninstaller modifies system directories or package receipts — operations
    /// that require administrator privileges.
    public let requiresSudo: Bool

    public init(
        token: String,
        version: String,
        autoUpdates: Bool,
        installedAppNames: [String],
        installDate: Date?,
        isOrphaned: Bool = false,
        requiresSudo: Bool = false
    ) {
        self.id = token
        self.token = token
        self.version = version
        self.autoUpdates = autoUpdates
        self.installedAppNames = installedAppNames
        self.installDate = installDate
        self.isOrphaned = isOrphaned
        self.requiresSudo = requiresSudo
    }
}
