import Foundation

/// Gathers the project roots `ProjectArtifactsRule` scans: discovered and confirmed, plus manual scan paths.
public enum ProjectRootGathering {
    public static func registeredRoots(
        discovery: ProjectRootDiscovery = .shared,
        pathStore: ProjectScanPathStore = .shared
    ) async -> [URL] {
        let discovered = await discovery.confirmedRoots()
        var seen = Set<String>()
        return (discovered + pathStore.paths.map { URL(fileURLWithPath: $0) })
            .filter { seen.insert(ScanPolicy.canonicalPathKey($0.path)).inserted }
    }
}
