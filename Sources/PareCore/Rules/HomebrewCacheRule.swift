import Foundation

/// Homebrew download and metadata cache under ~/Library/Caches/Homebrew.
/// Bottles, cask packages, API cache, and bootsnap are reconstructible.
public struct HomebrewCacheRule: ScanRule {
    public let id = "homebrew-cache"
    public let title = "Homebrew Download Cache"
    public let reason = "Homebrew cache (bottles/casks/API — reconstructible on demand)"
    public let category: ScanCategory = .developerPackageCaches
    public let riskLevel: RiskLevel = .safe
    public let confidence: Double = 0.97

    public init() {}

    public func targetDirectories(environment: ScanEnvironment) -> [URL] { [] }
    public func include(fileURL: URL, resourceValues: URLResourceValues) -> Bool { false }

    public func customScan(environment: ScanEnvironment) async -> [ScanFinding]? {
        let root = environment.homeDirectory.appending(path: "Library/Caches/Homebrew")
        return PackageManagerCachesRule.directoryFindings(
            at: root,
            category: category,
            riskLevel: riskLevel,
            reason: reason,
            confidence: confidence
        )
    }
}
