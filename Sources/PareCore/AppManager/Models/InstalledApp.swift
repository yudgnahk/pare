import Foundation

public struct InstalledApp: Identifiable, Sendable {
    public let id: String  // bundle ID, or path if bundle ID is missing
    public let name: String
    public let bundleID: String?
    public let version: String
    public let buildVersion: String
    public let path: String
    public var sizeBytes: Int64
    public let installDate: Date?
    public let lastUsed: Date?
    public let isMAS: Bool
    public let isSystemApp: Bool
    public var isHomebrewManaged: Bool
    public var updateInfo: UpdateInfo?

    public init(
        name: String,
        bundleID: String?,
        version: String,
        buildVersion: String,
        path: String,
        sizeBytes: Int64,
        installDate: Date?,
        lastUsed: Date?,
        isMAS: Bool,
        isSystemApp: Bool,
        isHomebrewManaged: Bool = false,
        updateInfo: UpdateInfo? = nil
    ) {
        self.id = bundleID ?? path
        self.name = name
        self.bundleID = bundleID
        self.version = version
        self.buildVersion = buildVersion
        self.path = path
        self.sizeBytes = sizeBytes
        self.installDate = installDate
        self.lastUsed = lastUsed
        self.isMAS = isMAS
        self.isSystemApp = isSystemApp
        self.isHomebrewManaged = isHomebrewManaged
        self.updateInfo = updateInfo
    }
}
