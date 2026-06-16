import Foundation

public struct DockerVMDataAdvancedRule: ScanRule {
    public let id = "docker-vm-data-advanced"
    public let title = "Docker VM Storage (Advanced — Use Docker-native cleanup)"
    public let reason = "Docker VM disk image — use 'docker system prune' instead of direct deletion"
    public let category: ScanCategory = .developerPackageCaches
    public let riskLevel: RiskLevel = .advanced
    public let confidence: Double = 0.6

    public init() {}

    public func targetDirectories(environment: ScanEnvironment) -> [URL] {
        [
            environment.homeDirectory.appending(path: "Library/Containers/com.docker.docker/Data/vms/0/data")
        ]
    }

    public func include(fileURL: URL, resourceValues: URLResourceValues) -> Bool {
        guard ScanPolicy.matchesPersonaPath(fileURL, allowedMarkers: ScanPolicy.developerDockerAdvancedPathMarkers) else {
            return false
        }

        return true
    }
}
