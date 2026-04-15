import Foundation

public struct DesignerReviewRequiredMediaRule: ScanRule {
    public let id = "designer-review-required-media"
    public let title = "Designer Media Caches (Review Required)"
    public let category: ScanCategory = .designerCaches
    public let riskLevel: RiskLevel = .review
    public let confidence: Double = 0.78

    public init() {}

    public func targetDirectories(environment: ScanEnvironment) -> [URL] {
        [
            environment.homeDirectory.appending(path: "Library/Application Support/Adobe/Common/Peak Files"),
            environment.homeDirectory.appending(path: "Movies/Adobe Premiere Pro Video Previews"),
            environment.homeDirectory.appending(path: "Movies/Adobe After Effects Disk Cache")
        ]
    }

    public func include(fileURL: URL, resourceValues: URLResourceValues) -> Bool {
        guard ScanPolicy.matchesPersonaPath(fileURL, allowedMarkers: ScanPolicy.designerReviewPathMarkers) else {
            return false
        }

        return ScanPolicy.passesMinimumAge(
            for: resourceValues,
            minimumAgeSeconds: ScanPolicy.defaultMinimumAgeSeconds(for: category)
        )
    }
}
