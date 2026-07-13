import Foundation

public enum UpdateChannel: String, Sendable {
    case sparkle
    case mas
}

public struct UpdateInfo: Sendable {
    public let bundleID: String
    public let installedVersion: String
    public let availableVersion: String
    public let channel: UpdateChannel
    /// Direct link to the appcast item download (Sparkle) or MAS deep link.
    public let updateURL: URL?

    /// True when the available version is strictly newer than the installed one.
    public var hasUpdate: Bool {
        FileSystemUtils.compareVersionStrings(availableVersion, installedVersion) == .orderedDescending
    }

    public init(
        bundleID: String,
        installedVersion: String,
        availableVersion: String,
        channel: UpdateChannel,
        updateURL: URL? = nil
    ) {
        self.bundleID = bundleID
        self.installedVersion = installedVersion
        self.availableVersion = availableVersion
        self.channel = channel
        self.updateURL = updateURL
    }
}
