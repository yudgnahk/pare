import Foundation

public struct BrewOutdatedPackage: Identifiable, Sendable {
    public let id: String
    public let name: String
    public let installedVersions: [String]
    public let currentVersion: String
    public let pinned: Bool
    public let isAutoUpdate: Bool
    public let isFormula: Bool

    public init(
        name: String,
        installedVersions: [String],
        currentVersion: String,
        pinned: Bool,
        isAutoUpdate: Bool,
        isFormula: Bool
    ) {
        self.id = name
        self.name = name
        self.installedVersions = installedVersions
        self.currentVersion = currentVersion
        self.pinned = pinned
        self.isAutoUpdate = isAutoUpdate
        self.isFormula = isFormula
    }
}
