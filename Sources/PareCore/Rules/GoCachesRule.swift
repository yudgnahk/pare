import Foundation

/// Go's build cache (`GOCACHE`) and module cache (`GOMODCACHE`) as whole folders, report-only.
/// Both are a working set Go manages itself, so findings are `.advanced`: shown with their size,
/// excluded from reclaimable totals, and hard-blocked by `CleanupEngine`.
public struct GoCachesRule: ScanRule {
    public let id = "go-caches"
    public let title = "Go Build & Module Caches"
    public let reason = "Go cache in active use — Go manages it itself (report-only)"
    public let category: ScanCategory = .developerPackageCaches
    public let riskLevel: RiskLevel = .advanced
    public let confidence: Double = 0.95

    /// Go deletes build-cache entries unused for this many days on its own.
    public static let buildCacheSelfTrimDays = 5

    private let locations: GoCacheLocations

    public init(locations: GoCacheLocations = .shared) {
        self.locations = locations
    }

    public func targetDirectories(environment: ScanEnvironment) -> [URL] { [] }
    public func include(fileURL: URL, resourceValues: URLResourceValues) -> Bool { false }

    public func customScan(environment: ScanEnvironment) async -> [ScanFinding]? {
        let home = environment.homeDirectory
        let reported = await locations.resolveIfNeeded()
        let targets: [(url: URL?, isModuleCache: Bool)] = [
            (reported.build, false),
            (reported.module, true),
            (home.appending(path: "Library/Caches/go-build"), false),
            (home.appending(path: "go/pkg/mod"), true),
        ]

        var seen = Set<String>()
        var findings: [ScanFinding] = []
        for target in targets {
            guard let root = target.url,
                  seen.insert(ScanPolicy.canonicalPathURL(root).path.lowercased()).inserted else { continue }
            // Go never trims the module cache on its own.
            let annotation = FindingAnnotation.workingSet(
                selfTrimDays: target.isModuleCache ? nil : Self.buildCacheSelfTrimDays
            )
            findings += ScanFindingBuilder.directoryFindings(
                at: root,
                category: category,
                riskLevel: riskLevel,
                reason: Self.reason(for: annotation),
                confidence: confidence,
                sizeIndex: environment.sizeIndex
            ).map { $0.annotated(with: annotation) }
        }
        return findings
    }

    private static func reason(for annotation: FindingAnnotation) -> String {
        switch annotation {
        case .workingSet(let days?):
            return "Go build cache in active use — Go evicts entries unused for \(days) days itself (report-only)"
        case .workingSet(nil):
            return "Go module cache shared by every Go project — clear with `go clean -modcache` if needed (report-only)"
        }
    }
}

private extension ScanFinding {
    func annotated(with annotation: FindingAnnotation) -> ScanFinding {
        ScanFinding(
            category: category,
            riskLevel: riskLevel,
            reason: reason,
            path: path,
            sizeBytes: sizeBytes,
            lastUsed: lastUsed,
            confidence: confidence,
            annotations: annotations + [annotation]
        )
    }
}
