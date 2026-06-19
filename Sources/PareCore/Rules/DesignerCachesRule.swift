import Foundation

public struct DesignerCachesRule: ScanRule {
    public let id = "designer-caches"
    public let title = "Designer Caches (Adobe/Figma)"
    public let reason = "Adobe or Figma rendering cache (regenerated automatically)"
    public let category: ScanCategory = .designerCaches
    public let riskLevel: RiskLevel = .safe
    public let confidence: Double = 0.9

    public init() {}

    public func targetDirectories(environment: ScanEnvironment) -> [URL] {
        [
            environment.homeDirectory.appending(path: "Library/Caches/Adobe"),
            environment.homeDirectory.appending(path: "Library/Caches/com.adobe"),
            environment.homeDirectory.appending(path: "Library/Caches/com.figma.desktop"),
            environment.homeDirectory.appending(path: "Library/Application Support/Adobe/Common/Media Cache"),
            environment.homeDirectory.appending(path: "Library/Application Support/Figma/Cache"),
            environment.homeDirectory.appending(path: "Library/Application Support/Figma/Desktop/Cache")
        ]
    }

    public func include(fileURL: URL, resourceValues: URLResourceValues) -> Bool {
        guard ScanPolicy.matchesPersonaPath(fileURL, allowedMarkers: ScanPolicy.designerSafePathMarkers) else {
            return false
        }

        return ScanPolicy.passesMinimumAge(
            for: resourceValues,
            minimumAgeSeconds: ScanPolicy.defaultMinimumAgeSeconds(for: category)
        )
    }
}
