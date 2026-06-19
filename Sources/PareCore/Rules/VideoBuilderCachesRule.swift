import Foundation

public struct VideoBuilderCachesRule: ScanRule {
    public let id = "video-builder-caches"
    public let title = "Video Builder Caches (FCP/Premiere/Resolve)"
    public let reason = "Video editor render cache (regenerated on next render)"
    public let category: ScanCategory = .videoBuilderCaches
    public let riskLevel: RiskLevel = .safe
    public let confidence: Double = 0.9

    public init() {}

    public func targetDirectories(environment: ScanEnvironment) -> [URL] {
        [
            environment.homeDirectory.appending(path: "Library/Caches/com.apple.FinalCut"),
            environment.homeDirectory.appending(path: "Library/Caches/Adobe/Premiere"),
            environment.homeDirectory.appending(path: "Library/Caches/Adobe/After Effects"),
            environment.homeDirectory.appending(path: "Library/Caches/Blackmagic Design/DaVinci Resolve"),
            environment.homeDirectory.appending(path: "Library/Application Support/Blackmagic Design/DaVinci Resolve/Cache")
        ]
    }

    public func include(fileURL: URL, resourceValues: URLResourceValues) -> Bool {
        guard ScanPolicy.matchesPersonaPath(fileURL, allowedMarkers: ScanPolicy.videoBuilderSafePathMarkers) else {
            return false
        }

        return ScanPolicy.passesMinimumAge(
            for: resourceValues,
            minimumAgeSeconds: ScanPolicy.defaultMinimumAgeSeconds(for: category)
        )
    }
}
