import Foundation

public struct BrewCask: Identifiable, Sendable {
    public let id: String
    public let token: String
    public let version: String
    public let autoUpdates: Bool
    public let installedAppNames: [String]
    public let installDate: Date?

    public init(
        token: String,
        version: String,
        autoUpdates: Bool,
        installedAppNames: [String],
        installDate: Date?
    ) {
        self.id = token
        self.token = token
        self.version = version
        self.autoUpdates = autoUpdates
        self.installedAppNames = installedAppNames
        self.installDate = installDate
    }
}
