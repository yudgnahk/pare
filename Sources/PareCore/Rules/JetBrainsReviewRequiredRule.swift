import Foundation

public struct JetBrainsReviewRequiredRule: ScanRule {
    public let id = "jetbrains-review-required"
    public let title = "JetBrains Plugins and Drivers (Review Required)"
    public let reason = "JetBrains IDE plugin or JDBC driver data (review before removing)"
    public let category: ScanCategory = .developerPackageCaches
    public let riskLevel: RiskLevel = .review
    public let confidence: Double = 0.8

    public init() {}

    public func targetDirectories(environment: ScanEnvironment) -> [URL] {
        [
            environment.homeDirectory.appending(path: "Library/Application Support/JetBrains")
        ]
    }

    public func include(fileURL: URL, resourceValues: URLResourceValues) -> Bool {
        let path = fileURL.path.lowercased()

        // Marker pairs live in ScanPolicy (R1.4).
        guard ScanPolicy.isJetBrainsReviewRequiredPath(fileURL) else {
            return false
        }

        guard ScanPolicy.matchesPersonaPath(fileURL, allowedMarkers: ScanPolicy.developerReviewPathMarkers) else {
            return false
        }

        let hasExcludedMarker = ScanPolicy.developerReviewExclusionMarkers.contains { path.contains($0) }
        guard !hasExcludedMarker else {
            return false
        }

        return ScanPolicy.passesMinimumAge(
            for: resourceValues,
            minimumAgeSeconds: ScanPolicy.defaultMinimumAgeSeconds(for: category)
        )
    }
}
