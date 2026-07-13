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
            environment.homeDirectory.appending(path: "Library/Caches/BraveSoftware"),
            environment.homeDirectory.appending(path: "Library/Caches/Microsoft Edge"),
            environment.homeDirectory.appending(path: "Library/Caches/com.operasoftware.Opera"),
            environment.homeDirectory.appending(path: "Library/Application Support/Arc/User Data/Default/Cache"),
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

        // Browser HTTP caches are actively rewritten while the browser runs.
        // A multi-day age gate hides nearly all reclaimable Chrome/Safari cache
        // (CleanMyMac/Mole still list it). Safe to clean regardless of age.
        return true
    }
}
