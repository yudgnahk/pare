import Foundation

/// Cleans reconstructible cache files written by AI coding tools.
/// Targets are driven by `app-catalog.json` (category "ai") — add new tools there.
public struct AIToolCachesRule: ScanRule {
    public let id = "ai-tool-caches"
    public let title = "AI Tool Caches"
    public let reason = "AI coding tool cache (safe to regenerate)"
    public let category: ScanCategory = .aiToolCaches
    public let riskLevel: RiskLevel = .safe
    public let confidence: Double = 0.95

    public init() {}

    public func targetDirectories(environment: ScanEnvironment) -> [URL] {
        let home = environment.homeDirectory
        let library = home.appending(path: "Library")
        return AppCatalog.shared.entries(forCategory: "ai").flatMap { entry -> [URL] in
            let libURLs = entry.libraryPaths.map { library.appending(path: $0) }
            let homeURLs = entry.homePaths.map { home.appending(path: $0) }
            return libURLs + homeURLs
        }
    }

    public func include(fileURL: URL, resourceValues: URLResourceValues) -> Bool {
        guard ScanPolicy.isLowImpactPath(fileURL)
                || ScanPolicy.matchesPersonaPath(fileURL, allowedMarkers: ScanPolicy.aiToolSafePathMarkers) else {
            return false
        }
        return ScanPolicy.passesMinimumAge(
            for: resourceValues,
            minimumAgeSeconds: ScanPolicy.defaultMinimumAgeSeconds(for: category)
        )
    }
}
