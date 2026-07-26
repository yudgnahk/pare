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

    /// Throwing variant invoked by `ScanRunner` (R1.2). Rules whose scan can fail
    /// meaningfully override this so "rule failed" is distinguishable from
    /// "rule found nothing" — failures surface as `ScanReport.ruleFailures`.
    func customScanThrowing(environment: ScanEnvironment) async throws -> [ScanFinding]?
}

public extension ScanRule {
    /// Default: use the standard per-file traversal path.
    func customScan(environment: ScanEnvironment) async -> [ScanFinding]? { nil }

    /// Default: delegate to the non-throwing `customScan`.
    func customScanThrowing(environment: ScanEnvironment) async throws -> [ScanFinding]? {
        await customScan(environment: environment)
    }
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

/// Traversal output including the locations that could not be read (R1.3).
public struct TraversalResult: Sendable {
    public let files: [ScannedFile]
    /// Paths (files or directories) skipped because of permission/read errors.
    public let unreadablePaths: Set<String>

    public init(files: [ScannedFile], unreadablePaths: Set<String> = []) {
        self.files = files
        self.unreadablePaths = unreadablePaths
    }
}

public protocol FileTraversing: Sendable {
    func collectFiles(in directories: [URL]) async -> [ScannedFile]

    /// Like `collectFiles`, but also reports unreadable locations so callers can
    /// distinguish "empty" from "not allowed to look" (R1.3 / Full Disk Access).
    func collectFilesReportingErrors(in directories: [URL]) async -> TraversalResult
}

public extension FileTraversing {
    /// Default: no diagnostics — implementations that can observe permission
    /// errors override this.
    func collectFilesReportingErrors(in directories: [URL]) async -> TraversalResult {
        TraversalResult(files: await collectFiles(in: directories))
    }
}
