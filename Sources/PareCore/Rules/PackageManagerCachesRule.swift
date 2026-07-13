import Foundation

public struct PackageManagerCachesRule: ScanRule {
    public let id = "package-manager-caches"
    public let title = "Package Manager Caches"
    public let reason = "Package manager download cache (npm/Yarn/pnpm/CocoaPods/SwiftPM)"
    public let category: ScanCategory = .developerPackageCaches
    public let riskLevel: RiskLevel = .safe
    public let confidence: Double = 0.95

    public init() {}

    public func targetDirectories(environment: ScanEnvironment) -> [URL] {
        [
            environment.homeDirectory.appending(path: ".npm/_cacache"),
            // npx package extract cache — often larger than _cacache (Mole parity).
            environment.homeDirectory.appending(path: ".npm/_npx"),
            environment.homeDirectory.appending(path: "Library/Caches/Yarn"),
            environment.homeDirectory.appending(path: "Library/Caches/pnpm"),
            environment.homeDirectory.appending(path: "Library/Caches/CocoaPods"),
            environment.homeDirectory.appending(path: "Library/Caches/org.swift.swiftpm")
        ]
    }

    public func include(fileURL: URL, resourceValues: URLResourceValues) -> Bool {
        let path = fileURL.path
        // Persona markers for home-relative npm paths (not under Library/Caches).
        let npmMarkers = ["/.npm/_cacache", "/.npm/_npx"]
        let allowed = ScanPolicy.isLowImpactPath(fileURL)
            || npmMarkers.contains(where: { path.contains($0) })
        guard allowed else { return false }

        // npx extracts are disposable package trees; skip multi-day age gate.
        if path.contains("/.npm/_npx") { return true }

        return ScanPolicy.passesMinimumAge(
            for: resourceValues,
            minimumAgeSeconds: ScanPolicy.defaultMinimumAgeSeconds(for: category)
        )
    }
}
