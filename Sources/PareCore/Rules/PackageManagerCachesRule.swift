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
            environment.homeDirectory.appending(path: "Library/Caches/Yarn"),
            environment.homeDirectory.appending(path: "Library/Caches/pnpm"),
            environment.homeDirectory.appending(path: "Library/Caches/CocoaPods"),
            environment.homeDirectory.appending(path: "Library/Caches/org.swift.swiftpm")
        ]
    }

    public func include(fileURL: URL, resourceValues: URLResourceValues) -> Bool {
        guard ScanPolicy.isLowImpactPath(fileURL) else {
            return false
        }

        return ScanPolicy.passesMinimumAge(
            for: resourceValues,
            minimumAgeSeconds: ScanPolicy.defaultMinimumAgeSeconds(for: category)
        )
    }
}
