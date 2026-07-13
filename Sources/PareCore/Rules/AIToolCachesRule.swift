import Foundation

/// Reconstructible AI coding-tool caches as whole folders.
/// Targets come from `app-catalog.json` (category "ai") plus known log/snapshot paths.
public struct AIToolCachesRule: ScanRule {
    public let id = "ai-tool-caches"
    public let title = "AI Tool Caches"
    public let reason = "AI coding tool cache (safe to regenerate)"
    public let category: ScanCategory = .aiToolCaches
    public let riskLevel: RiskLevel = .safe
    public let confidence: Double = 0.95

    public init() {}

    public func targetDirectories(environment: ScanEnvironment) -> [URL] { [] }
    public func include(fileURL: URL, resourceValues: URLResourceValues) -> Bool { false }

    public func customScan(environment: ScanEnvironment) async -> [ScanFinding]? {
        let home = environment.homeDirectory
        let library = home.appending(path: "Library")

        var targets: [(URL, String)] = AppCatalog.shared.entries(forCategory: "ai").flatMap { entry in
            let lib = entry.libraryPaths.map {
                (library.appending(path: $0), "\(entry.displayName) cache — reconstructible")
            }
            let homePaths = entry.homePaths.map {
                (home.appending(path: $0), "\(entry.displayName) cache — reconstructible")
            }
            return lib + homePaths
        }

        // OpenCode also keeps regenerable logs/snapshots outside .cache.
        targets += [
            (home.appending(path: ".local/share/opencode/log"),
             "OpenCode log cache — reconstructible"),
            (home.appending(path: ".local/share/opencode/snapshot"),
             "OpenCode snapshot cache — reconstructible"),
        ]

        var findings: [ScanFinding] = []
        var seen = Set<String>()
        for (url, reason) in targets {
            let path = url.path
            guard seen.insert(path).inserted else { continue }
            findings += PackageManagerCachesRule.directoryFindings(
                at: url,
                category: category,
                riskLevel: riskLevel,
                reason: reason,
                confidence: confidence
            )
        }
        return findings
    }
}
