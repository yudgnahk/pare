import Foundation

/// Extends Docker Desktop coverage beyond the existing `DockerLogsReviewRequiredRule`.
///
/// Safe-to-delete paths (daemon logs, lifecycle logs, UI logs):
///   - `~/Library/Containers/com.docker.docker/Data/log/`
///   - `~/Library/Containers/com.docker.docker/Data/lifecycle-server.log*`
///   - `~/Library/Group Containers/group.com.docker/log/`
///
/// Detect-only (`.advanced`):
///   - `~/Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw`
///     — Docker VM disk image. Cannot be safely deleted; report only.
///     "Run Docker system prune in Maintenance tab to reclaim space safely."
public struct DockerStorageRule: ScanRule {
    public let id = "docker-storage"
    public let title = "Docker Desktop Storage"
    public let reason = "Docker Desktop log files and VM disk image"
    public let category: ScanCategory = .developerPackageCaches
    public let riskLevel: RiskLevel = .safe  // most findings are safe; Docker.raw is advanced
    public let confidence: Double = 0.90

    public init() {}

    public func targetDirectories(environment: ScanEnvironment) -> [URL] { [] }
    public func include(fileURL: URL, resourceValues: URLResourceValues) -> Bool { false }

    public func customScan(environment: ScanEnvironment) async -> [ScanFinding]? {
        let home = environment.homeDirectory
        var findings: [ScanFinding] = []

        // -- Safe log paths --
        let safeLogPaths: [(String, String)] = [
            ("Library/Containers/com.docker.docker/Data/log", "Docker Desktop daemon logs"),
            ("Library/Group Containers/group.com.docker/log", "Docker Desktop UI logs"),
        ]
        for (relPath, reason) in safeLogPaths {
            let url = home.appending(path: relPath)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            let size = FileSystemUtils.directorySize(url: url)
            guard size > 0 else { continue }
            let resourceValues = try? url.resourceValues(forKeys: [.contentModificationDateKey])
            let lastUsed = resourceValues?.contentModificationDate

            if let date = lastUsed,
               Date().timeIntervalSince(date) < ScanPolicy.defaultCacheMinAgeSeconds {
                continue
            }

            findings.append(ScanFinding(
                category: category,
                riskLevel: .safe,
                reason: reason,
                path: url.path,
                sizeBytes: size,
                lastUsed: lastUsed,
                confidence: confidence
            ))
        }

        // -- Detect-only Docker.raw (.advanced) --
        let dockerRaw = home.appending(path: "Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw")
        if FileManager.default.fileExists(atPath: dockerRaw.path) {
            let size = (try? FileManager.default.attributesOfItem(atPath: dockerRaw.path))?[.size] as? Int64 ?? 0
            if size > 0 {
                let resourceValues = try? dockerRaw.resourceValues(forKeys: [.contentModificationDateKey])
                let lastUsed = resourceValues?.contentModificationDate

                findings.append(ScanFinding(
                    category: category,
                    riskLevel: .advanced,
                    reason: "Docker VM disk image — use 'docker system prune' to reclaim space safely",
                    path: dockerRaw.path,
                    sizeBytes: size,
                    lastUsed: lastUsed,
                    confidence: 0.95
                ))
            }
        }

        return findings
    }
}
