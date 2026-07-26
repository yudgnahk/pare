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
    /// Memoized directory sizing shared by all rules within one scan.
    /// `ScanRunner.run` swaps in a fresh index per run via `withFreshSizeIndex()`
    /// so sizes are never reused across scans.
    public let sizeIndex: DirectorySizeIndex

    public init(
        homeDirectory: URL,
        tempDirectory: URL = FileManager.default.temporaryDirectory,
        sizeIndex: DirectorySizeIndex = DirectorySizeIndex()
    ) {
        self.homeDirectory = homeDirectory
        self.tempDirectory = tempDirectory
        self.sizeIndex = sizeIndex
    }

    public static func current() -> ScanEnvironment {
        ScanEnvironment(homeDirectory: FileManager.default.homeDirectoryForCurrentUser)
    }

    /// Copy of this environment with an empty size index (per-scan memoization).
    public func withFreshSizeIndex() -> ScanEnvironment {
        ScanEnvironment(
            homeDirectory: homeDirectory,
            tempDirectory: tempDirectory,
            sizeIndex: DirectorySizeIndex()
        )
    }
}

public protocol FileTraversing: Sendable {
    func collectFiles(in directories: [URL]) async -> [ScannedFile]

    /// Single-directory variant. Implementations that fan out over a task group
    /// in the array overload should provide a direct path here so per-directory
    /// callers (e.g. `CachedFileTraversal`) don't pay for a one-child group.
    func collectFiles(in directory: URL) async -> [ScannedFile]
}

public extension FileTraversing {
    /// Default: forward to the array overload (correct for any conformer).
    func collectFiles(in directory: URL) async -> [ScannedFile] {
        await collectFiles(in: [directory])
    }
}
