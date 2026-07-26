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
    /// Memoized directory sizing shared by all rules within one scan.
    /// `ScanRunner.run` swaps in a fresh index per run via `withFreshSizeIndex()`
    /// so sizes are never reused across scans.
    public let sizeIndex: DirectorySizeIndex
    /// Machine-wide application directories scanned by app-level rules.
    ///
    /// Injectable because a hardcoded absolute `/Applications` escapes an injected
    /// fake home and scans the real machine — which made integration tests depend on
    /// whatever the host had installed (CI runners ship several Xcode versions, so
    /// `StaleAppVersionRule` legitimately reported them and the suite failed there).
    /// Rules must take system roots from here, never from a literal.
    public let systemApplicationDirectories: [URL]

    public static let defaultSystemApplicationDirectories: [URL] = [
        URL(fileURLWithPath: "/Applications")
    ]

    public init(
        homeDirectory: URL,
        tempDirectory: URL = FileManager.default.temporaryDirectory,
        sizeIndex: DirectorySizeIndex = DirectorySizeIndex(),
        systemApplicationDirectories: [URL] = ScanEnvironment.defaultSystemApplicationDirectories
    ) {
        self.homeDirectory = homeDirectory
        self.tempDirectory = tempDirectory
        self.sizeIndex = sizeIndex
        self.systemApplicationDirectories = systemApplicationDirectories
    }

    public static func current() -> ScanEnvironment {
        ScanEnvironment(homeDirectory: FileManager.default.homeDirectoryForCurrentUser)
    }

    /// Copy of this environment with an empty size index (per-scan memoization).
    public func withFreshSizeIndex() -> ScanEnvironment {
        ScanEnvironment(
            homeDirectory: homeDirectory,
            tempDirectory: tempDirectory,
            sizeIndex: DirectorySizeIndex(),
            systemApplicationDirectories: systemApplicationDirectories
        )
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

    /// Single-directory variant. Implementations that fan out over a task group
    /// in the array overload should provide a direct path here so per-directory
    /// callers (e.g. `CachedFileTraversal`) don't pay for a one-child group.
    func collectFiles(in directory: URL) async -> [ScannedFile]

    /// Single-directory variant of `collectFilesReportingErrors` — same
    /// no-task-group rationale as the single-directory `collectFiles`.
    func collectFilesReportingErrors(in directory: URL) async -> TraversalResult
}

public extension FileTraversing {
    /// Default: no diagnostics — implementations that can observe permission
    /// errors override this.
    func collectFilesReportingErrors(in directories: [URL]) async -> TraversalResult {
        TraversalResult(files: await collectFiles(in: directories))
    }

    /// Default: forward to the array overload (correct for any conformer).
    func collectFilesReportingErrors(in directory: URL) async -> TraversalResult {
        await collectFilesReportingErrors(in: [directory])
    }

    /// Default: forward to the array overload (correct for any conformer).
    func collectFiles(in directory: URL) async -> [ScannedFile] {
        await collectFiles(in: [directory])
    }
}
