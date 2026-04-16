import Foundation

public struct VSCodeCachesRule: ScanRule {
    public let id = "vscode-caches"
    public let title = "VS Code Caches"
    public let category: ScanCategory = .developerPackageCaches
    public let riskLevel: RiskLevel = .safe
    public let confidence: Double = 0.96

    public init() {}

    public func targetDirectories(environment: ScanEnvironment) -> [URL] {
        [
            environment.homeDirectory.appending(path: "Library/Caches/com.microsoft.VSCode.ShipIt"),
            environment.homeDirectory.appending(path: "Library/Application Support/Code/CachedExtensionVSIXs")
        ]
    }

    public func include(fileURL: URL, resourceValues: URLResourceValues) -> Bool {
        guard ScanPolicy.matchesPersonaPath(fileURL, allowedMarkers: ScanPolicy.developerSafePathMarkers) else {
            return false
        }

        return ScanPolicy.passesMinimumAge(
            for: resourceValues,
            minimumAgeSeconds: ScanPolicy.defaultMinimumAgeSeconds(for: category)
        )
    }
}
