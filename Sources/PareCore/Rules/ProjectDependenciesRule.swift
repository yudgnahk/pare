import Foundation

/// Offers `node_modules` / `venv` / `.venv` / `.bundle` of projects idle longer than the disk-pressure
/// tier allows, for review only. Every condition lives in `ScanPolicy.isReclaimableProjectDependency`,
/// which `CleanupEngine` re-checks; a reinstall is needed before the project builds again.
public struct ProjectDependenciesRule: ScanRule {
    public let id = "project-dependencies"
    public let title = "Dependencies of Inactive Projects"
    public let reason = "Dependency folder of an inactive project — reinstall before working on it again"
    public let category: ScanCategory = .projectArtifacts
    public let riskLevel: RiskLevel = .review
    public let confidence: Double = 0.8

    /// Same depth as `ProjectArtifactsRule`.
    static let maxDepth = 8

    private let rootsProvider: @Sendable () async -> [URL]
    private let diskPressure: @Sendable () -> DiskPressureTier
    private let now: @Sendable () -> Date
    private let minimumBytes: Int64

    public init(
        rootsProvider: (@Sendable () async -> [URL])? = nil,
        diskPressure: @escaping @Sendable () -> DiskPressureTier = { DiskPressure.current() },
        now: @escaping @Sendable () -> Date = { Date() },
        minimumBytes: Int64 = ScanPolicy.projectDependencyMinimumBytes
    ) {
        self.rootsProvider = rootsProvider ?? {
            await ProjectRootDiscovery.shared.discoverIfNeeded()
            let discovered = await ProjectRootDiscovery.shared.confirmedRoots()
            return discovered + ProjectScanPathStore.shared.paths.map { URL(fileURLWithPath: $0) }
        }
        self.diskPressure = diskPressure
        self.now = now
        self.minimumBytes = minimumBytes
    }

    public func targetDirectories(environment: ScanEnvironment) -> [URL] { [] }
    public func include(fileURL: URL, resourceValues: URLResourceValues) -> Bool { false }

    public func customScan(environment: ScanEnvironment) async -> [ScanFinding]? {
        var seen = Set<String>()
        let roots = await rootsProvider().filter { seen.insert($0.standardizedFileURL.path).inserted }
        guard !roots.isEmpty else { return [] }
        let tier = diskPressure()
        let rootPaths = roots.map(\.path)
        let scanTime = now()

        var candidates: [URL] = []
        for root in roots where !Task.isCancelled {
            collectDependencyFolders(in: root, depth: 0, into: &candidates)
        }
        var reported = Set<String>()
        return candidates.compactMap { url in
            guard reported.insert(url.standardizedFileURL.path).inserted,
                  ScanPolicy.isReclaimableProjectDependency(url, registeredRootPaths: rootPaths, tier: tier, now: scanTime),
                  let activity = ScanPolicy.projectActivityDate(projectRoot: url.deletingLastPathComponent()) else {
                return nil
            }
            let size = environment.sizeIndex.directorySize(url: url)
            guard size >= minimumBytes else { return nil }
            return ScanFinding(
                category: category,
                riskLevel: riskLevel,
                reason: reasonText(for: url, inactiveSince: activity, tier: tier, now: scanTime),
                path: url.path,
                sizeBytes: size,
                lastUsed: activity,
                confidence: confidence
            )
        }
    }

    /// Dependency folders below `directory`, never descending into them, `.git`, or build output.
    private func collectDependencyFolders(in directory: URL, depth: Int, into found: inout [URL]) {
        guard depth < Self.maxDepth, !Task.isCancelled,
              let entries = try? FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey]
              ) else { return }
        for entry in entries {
            guard let values = try? entry.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
                  values.isDirectory == true, values.isSymbolicLink != true else { continue }
            let lower = entry.lastPathComponent.lowercased()
            if ScanPolicy.isProjectDependencyDirectory(lower) {
                found.append(entry)
            } else if !lower.hasPrefix("."), !ScanPolicy.projectLocalArtifactDirectoryNames.contains(lower) {
                collectDependencyFolders(in: entry, depth: depth + 1, into: &found)
            }
        }
    }

    private func reasonText(for url: URL, inactiveSince activity: Date, tier: DiskPressureTier, now: Date) -> String {
        let days = max(0, Int((now.timeIntervalSince(activity) / (24 * 60 * 60)).rounded()))
        let threshold = Int(ScanPolicy.projectDependencyInactivitySeconds(for: tier) / (24 * 60 * 60))
        let pressure: String
        switch tier {
        case .comfortable: pressure = "\(threshold)-day threshold"
        case .low: pressure = "shown because free space is low (\(threshold)-day threshold)"
        case .critical: pressure = "shown because free space is critical (\(threshold)-day threshold)"
        }
        let restore = ScanPolicy.projectDependencyLockfile(for: url)
            .flatMap(ScanPolicy.projectDependencyRestoreCommand(lockfile:))
            .map { " · restore with `\($0)`" } ?? ""
        return "Inactive \(days) days · \(pressure)\(restore)"
    }
}
