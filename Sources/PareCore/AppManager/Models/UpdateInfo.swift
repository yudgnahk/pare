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

    public var hasUpdate: Bool {
        availableVersion != installedVersion
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
