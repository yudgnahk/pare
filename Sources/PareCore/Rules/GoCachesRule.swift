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
    private let moduleSizes: GoModuleCacheSizeStore

    public init(locations: GoCacheLocations = .shared, moduleSizes: GoModuleCacheSizeStore = .shared) {
        self.locations = locations
        self.moduleSizes = moduleSizes
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
            if let remembered = rememberedFinding(at: root, annotation: annotation) {
                findings.append(remembered)
                continue
            }
            let measured = ScanFindingBuilder.directoryFindings(
                at: root,
                category: category,
                riskLevel: riskLevel,
                reason: Self.reason(for: annotation),
                confidence: confidence,
                sizeIndex: environment.sizeIndex
            )
            if let finding = measured.first, finding.isSizeComplete {
                moduleSizes.remember(finding.sizeBytes, for: root)
            }
            findings += measured.map { $0.copy(annotations: $0.annotations + [annotation]) }
        }
        return findings
    }

    /// The cache's last complete size, when `GoModuleCacheSizeStore` still trusts it.
    private func rememberedFinding(at root: URL, annotation: FindingAnnotation) -> ScanFinding? {
        guard FileManager.default.fileExists(atPath: root.path),
              let bytes = moduleSizes.size(for: root), bytes > 0 else { return nil }
        return ScanFinding(
            category: category,
            riskLevel: riskLevel,
            reason: Self.reason(for: annotation),
            path: root.path,
            sizeBytes: bytes,
            lastUsed: try? root.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
            confidence: confidence,
            annotations: [annotation]
        )
    }

    private static func reason(for annotation: FindingAnnotation) -> String {
        switch annotation {
        case .workingSet(let days?):
            return "Go build cache in active use — Go evicts entries unused for \(days) days itself (report-only)"
        case .workingSet(nil):
            return "Go module cache shared by every Go project — clear with `go clean -modcache` if needed (report-only)"
        case .explainOnly(let action):
            return action
        case .deletedFilesHolder(let holder):
            return "Restart \(holder.displayName) to reclaim the space"
        case .noteAction:
            return ""
        }
    }
}
