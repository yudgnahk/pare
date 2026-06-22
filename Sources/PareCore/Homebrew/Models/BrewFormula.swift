import Foundation

public struct BrewFormula: Identifiable, Sendable {
    public let id: String
    public let name: String
    public let desc: String
    public let version: String
    public let installedOnRequest: Bool
    public let pinned: Bool
    public let installDate: Date?
    public let dependencies: [String]

    public init(
        name: String,
        desc: String,
        version: String,
        installedOnRequest: Bool,
        pinned: Bool,
        installDate: Date?,
        dependencies: [String]
    ) {
        self.id = name
        self.name = name
        self.desc = desc
        self.version = version
        self.installedOnRequest = installedOnRequest
        self.pinned = pinned
        self.installDate = installDate
        self.dependencies = dependencies
    }
}
