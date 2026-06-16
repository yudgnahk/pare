import Foundation

public struct DockerLogsReviewRequiredRule: ScanRule {
    public let id = "docker-logs-review-required"
    public let title = "Docker Desktop Logs (Review Required)"
    public let reason = "Docker Desktop log files (review before removing)"
    public let category: ScanCategory = .developerPackageCaches
    public let riskLevel: RiskLevel = .review
    public let confidence: Double = 0.8

    public init() {}

    public func targetDirectories(environment: ScanEnvironment) -> [URL] {
        [
            environment.homeDirectory.appending(path: "Library/Containers/com.docker.docker/Data/log")
        ]
    }

    public func include(fileURL: URL, resourceValues: URLResourceValues) -> Bool {
        guard ScanPolicy.matchesPersonaPath(fileURL, allowedMarkers: ScanPolicy.developerDockerReviewPathMarkers) else {
            return false
        }

        return true
    }
}
