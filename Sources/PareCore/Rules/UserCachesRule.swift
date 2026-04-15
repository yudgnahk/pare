import Foundation

public struct UserCachesRule: ScanRule {
    public let id = "user-caches"
    public let title = "User Cache Folders"
    public let category: ScanCategory = .userCaches
    public let riskLevel: RiskLevel = .safe
    public let confidence: Double = 0.95

    private let browserCacheMarkers = [
        "/Library/Caches/Google/Chrome",
        "/Library/Caches/com.apple.Safari",
        "/Library/Caches/Firefox",
        "/Library/Caches/BraveSoftware"
    ]

    private let developerSpecificMarkers = [
        "/Library/Developer/Xcode/DerivedData",
        "/Library/Developer/Xcode/Archives",
        "/Library/Developer/CoreSimulator",
        "/Library/Caches/Yarn",
        "/Library/Caches/pnpm",
        "/Library/Caches/CocoaPods",
        "/Library/Caches/org.swift.swiftpm",
        "/.npm/_cacache"
    ]

    public init() {}

    public func targetDirectories(environment: ScanEnvironment) -> [URL] {
        [environment.homeDirectory.appending(path: "Library/Caches")]
    }

    public func include(fileURL: URL, resourceValues: URLResourceValues) -> Bool {
        let path = fileURL.path
        if browserCacheMarkers.contains(where: { path.contains($0) }) {
            return false
        }

        if developerSpecificMarkers.contains(where: { path.contains($0) }) {
            return false
        }

        return true
    }
}
