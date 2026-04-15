import Foundation

public protocol ScanRule: Sendable {
    var id: String { get }
    var title: String { get }
    var category: ScanCategory { get }
    var riskLevel: RiskLevel { get }
    var confidence: Double { get }

    func targetDirectories(environment: ScanEnvironment) -> [URL]
    func include(fileURL: URL, resourceValues: URLResourceValues) -> Bool
}

public struct ScanEnvironment: Sendable {
    public let homeDirectory: URL
    public let tempDirectory: URL

    public init(homeDirectory: URL, tempDirectory: URL = FileManager.default.temporaryDirectory) {
        self.homeDirectory = homeDirectory
        self.tempDirectory = tempDirectory
    }

    public static func current() -> ScanEnvironment {
        ScanEnvironment(homeDirectory: FileManager.default.homeDirectoryForCurrentUser)
    }
}

public protocol FileTraversing: Sendable {
    func collectFiles(in directories: [URL]) async -> [ScannedFile]
}
