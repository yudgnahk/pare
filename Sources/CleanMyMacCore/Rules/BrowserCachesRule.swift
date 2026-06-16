import Foundation

public struct BrowserCachesRule: ScanRule {
    public let id = "browser-caches"
    public let title = "Browser Caches (Safe Subset)"
    public let reason = "Browser rendering or GPU cache"
    public let category: ScanCategory = .browserCaches
    public let riskLevel: RiskLevel = .review
    public let confidence: Double = 0.88

    public init() {}

    public func targetDirectories(environment: ScanEnvironment) -> [URL] {
        [
            environment.homeDirectory.appending(path: "Library/Caches/Google/Chrome"),
            environment.homeDirectory.appending(path: "Library/Caches/com.apple.Safari"),
            environment.homeDirectory.appending(path: "Library/Caches/Firefox"),
            environment.homeDirectory.appending(path: "Library/Caches/BraveSoftware")
        ]
    }

    public func include(fileURL: URL, resourceValues: URLResourceValues) -> Bool {
        let path = fileURL.path.lowercased()

        if path.contains("bookmarks") || path.contains("login") || path.contains("history") {
            return false
        }

        guard path.contains("cache") || path.contains("code cache") || path.contains("gpucache") else {
            return false
        }

        guard ScanPolicy.isLowImpactPath(fileURL) else {
            return false
        }

        return ScanPolicy.passesMinimumAge(
            for: resourceValues,
            minimumAgeSeconds: ScanPolicy.defaultMinimumAgeSeconds(for: category)
        )
    }
}
