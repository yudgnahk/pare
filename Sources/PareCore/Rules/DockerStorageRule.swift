import Foundation

/// Docker Desktop **log** coverage only.
///
/// Safe-to-delete paths (daemon / UI logs — not the VM disk):
///   - `~/Library/Containers/com.docker.docker/Data/log/`
///   - `~/Library/Group Containers/group.com.docker/log/`
///
/// The VM disk under `…/data/vms/` (including `Docker.raw`) is **never scanned as a finding**.
/// It is not a normal cache; it holds images, containers, build cache, and volumes.
/// CleanupEngine still path-blocks that tree via `ScanPolicy.isDockerNeverDeletePath`.
/// Users reclaim space with Maintenance → Docker System Prune (`docker system prune -f`, no `--volumes`).
public struct DockerStorageRule: ScanRule {
    public let id = "docker-storage"
    public let title = "Docker Desktop Logs"
    public let reason = "Docker Desktop log files"
    public let category: ScanCategory = .developerPackageCaches
    public let riskLevel: RiskLevel = .safe
    public let confidence: Double = 0.90

    public init() {}

    public func targetDirectories(environment: ScanEnvironment) -> [URL] { [] }
    public func include(fileURL: URL, resourceValues: URLResourceValues) -> Bool { false }

    public func customScan(environment: ScanEnvironment) async -> [ScanFinding]? {
        let home = environment.homeDirectory
        var findings: [ScanFinding] = []

        // Logs only — never the vms/ tree.
        let safeLogPaths: [(String, String)] = [
            ("Library/Containers/com.docker.docker/Data/log", "Docker Desktop daemon logs"),
            ("Library/Group Containers/group.com.docker/log", "Docker Desktop UI logs"),
        ]
        for (relPath, reason) in safeLogPaths {
            let url = home.appending(path: relPath)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            // Belt-and-suspenders if path layout ever changes.
            guard !ScanPolicy.isDockerNeverDeletePath(url) else { continue }

            let size = environment.sizeIndex.directorySize(url: url)
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

        return findings
    }
}
