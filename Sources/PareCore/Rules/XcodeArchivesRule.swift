import Foundation

public struct XcodeArchivesRule: ScanRule {
    public let id = "xcode-archives"
    public let title = "Xcode Archives"
    public let reason = "Xcode app archive (review before removing)"
    public let category: ScanCategory = .developerBuildArtifacts
    public let riskLevel: RiskLevel = .review
    public let confidence: Double = 0.9

    public init() {}

    public func targetDirectories(environment: ScanEnvironment) -> [URL] {
        [
            environment.homeDirectory.appending(path: "Library/Developer/Xcode/Archives")
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
