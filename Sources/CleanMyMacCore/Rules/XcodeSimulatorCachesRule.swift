import Foundation

public struct XcodeSimulatorCachesRule: ScanRule {
    public let id = "xcode-simulator-caches"
    public let title = "Xcode Simulator Caches"
    public let reason = "Simulator runtime cache (regenerated on next launch)"
    public let category: ScanCategory = .developerSimulatorCaches
    public let riskLevel: RiskLevel = .review
    public let confidence: Double = 0.85

    public init() {}

    public func targetDirectories(environment: ScanEnvironment) -> [URL] {
        [
            environment.homeDirectory.appending(path: "Library/Developer/CoreSimulator/Caches"),
            environment.homeDirectory.appending(path: "Library/Developer/CoreSimulator/Devices")
        ]
    }

    public func include(fileURL: URL, resourceValues: URLResourceValues) -> Bool {
        let path = fileURL.path.lowercased()
        if path.contains("data/containers") {
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
