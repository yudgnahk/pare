import Foundation

public struct XcodeDerivedDataRule: ScanRule {
    public let id = "xcode-derived-data"
    public let title = "Xcode DerivedData"
    public let reason = "Xcode build artefacts (regenerated on next build)"
    public let category: ScanCategory = .developerBuildArtifacts
    public let riskLevel: RiskLevel = .safe
    public let confidence: Double = 0.98

    public init() {}

    public func targetDirectories(environment: ScanEnvironment) -> [URL] {
        [
            environment.homeDirectory.appending(path: "Library/Developer/Xcode/DerivedData")
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
