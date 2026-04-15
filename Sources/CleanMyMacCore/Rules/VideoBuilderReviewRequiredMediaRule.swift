import Foundation

public struct VideoBuilderReviewRequiredMediaRule: ScanRule {
    public let id = "video-builder-review-required-media"
    public let title = "Video Builder Media Caches (Review Required)"
    public let category: ScanCategory = .videoBuilderCaches
    public let riskLevel: RiskLevel = .review
    public let confidence: Double = 0.76

    public init() {}

    public func targetDirectories(environment: ScanEnvironment) -> [URL] {
        [
            environment.homeDirectory.appending(path: "Movies/Final Cut Pro Render Files"),
            environment.homeDirectory.appending(path: "Movies/Final Cut Pro Backups"),
            environment.homeDirectory.appending(path: "Movies/Adobe Premiere Pro Video Previews"),
            environment.homeDirectory.appending(path: "Movies/Adobe After Effects Disk Cache"),
            environment.homeDirectory.appending(path: "Movies/DaVinci Resolve/CacheClip")
        ]
    }

    public func include(fileURL: URL, resourceValues: URLResourceValues) -> Bool {
        guard ScanPolicy.matchesPersonaPath(fileURL, allowedMarkers: ScanPolicy.videoBuilderReviewPathMarkers) else {
            return false
        }

        return ScanPolicy.passesMinimumAge(
            for: resourceValues,
            minimumAgeSeconds: ScanPolicy.defaultMinimumAgeSeconds(for: category)
        )
    }
}
