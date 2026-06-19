import Foundation

/// Cleans Homebrew's download cache (`~/Library/Caches/Homebrew/downloads/`).
/// After `brew install` or `brew upgrade`, Homebrew leaves downloaded bottles and cask
/// packages in this directory. They are never needed again — re-running the install
/// re-downloads them. Heavy Homebrew users can accumulate several GB here.
public struct HomebrewCacheRule: ScanRule {
    public let id = "homebrew-cache"
    public let title = "Homebrew Download Cache"
    public let reason = "Homebrew downloaded bottle or cask (safe to delete — re-downloaded on demand)"
    public let category: ScanCategory = .developerPackageCaches
    public let riskLevel: RiskLevel = .safe
    public let confidence: Double = 0.97

    // 1-day gate — avoids touching a file that is actively being downloaded.
    private static let minimumAgeSeconds: TimeInterval = 24 * 60 * 60

    public init() {}

    public func targetDirectories(environment: ScanEnvironment) -> [URL] {
        // Homebrew's download cache lives under ~/Library/Caches regardless of architecture
        // (Apple Silicon /opt/homebrew or Intel /usr/local — both write cache to ~/Library/Caches).
        [environment.homeDirectory.appending(path: "Library/Caches/Homebrew/downloads")]
    }

    public func include(fileURL: URL, resourceValues: URLResourceValues) -> Bool {
        // The Homebrew downloads path contains "/downloads/" which trips isLowImpactPath's
        // protected-path guard. Use matchesPersonaPath instead — the path is registered in
        // developerSafePathMarkers and personaProtectedPathOverrides.
        guard ScanPolicy.matchesPersonaPath(fileURL, allowedMarkers: ScanPolicy.developerSafePathMarkers) else {
            return false
        }
        return ScanPolicy.passesMinimumAge(
            for: resourceValues,
            minimumAgeSeconds: Self.minimumAgeSeconds
        )
    }
}
