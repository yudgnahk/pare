import Foundation

public protocol ScanRule: Sendable {
    var id: String { get }
    var title: String { get }
    /// Short human-readable explanation of why files matched by this rule are flagged.
    /// Shown in CLI output and app tooltips. Example: "Xcode build artefacts".
    var reason: String { get }
    var category: ScanCategory { get }
    var riskLevel: RiskLevel { get }
    var confidence: Double { get }

    func targetDirectories(environment: ScanEnvironment) -> [URL]
    func include(fileURL: URL, resourceValues: URLResourceValues) -> Bool

    /// Rules that need directory-level reasoning (e.g. comparing versions across
    /// sibling directories) can override this to produce findings directly.
    /// When a non-nil value is returned, `targetDirectories` and `include` are
    /// NOT called by `ScanRunner` for this rule.
    func customScan(environment: ScanEnvironment) async -> [ScanFinding]?
}

public extension ScanRule {
    /// Default: use the standard per-file traversal path.
    func customScan(environment: ScanEnvironment) async -> [ScanFinding]? { nil }
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
