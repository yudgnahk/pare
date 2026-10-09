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
    /// Directory entries listed per scan, across all roots, and the wall-clock cap on the whole walk.
    public static let defaultEntryBudget = 500_000
    public static let defaultTimeBudget: TimeInterval = 60

    private let rootsProvider: @Sendable () async -> [URL]
    private let diskPressure: @Sendable () -> DiskPressureTier
    private let now: @Sendable () -> Date
    private let minimumBytes: Int64
    private let entryBudget: Int
    private let timeBudget: TimeInterval

    public init(
        rootsProvider: (@Sendable () async -> [URL])? = nil,
        diskPressure: @escaping @Sendable () -> DiskPressureTier = { DiskPressure.current() },
        now: @escaping @Sendable () -> Date = { Date() },
        minimumBytes: Int64 = ScanPolicy.projectDependencyMinimumBytes,
        entryBudget: Int = ProjectDependenciesRule.defaultEntryBudget,
        timeBudget: TimeInterval = ProjectDependenciesRule.defaultTimeBudget
    ) {
        self.rootsProvider = rootsProvider ?? {
            await ProjectRootDiscovery.shared.discoverIfNeeded()
            let discovered = await ProjectRootDiscovery.shared.confirmedRoots()
            return discovered + ProjectScanPathStore.shared.paths.map { URL(fileURLWithPath: $0) }
        }
        self.diskPressure = diskPressure
        self.now = now
        self.minimumBytes = minimumBytes
        self.entryBudget = entryBudget
        self.timeBudget = timeBudget
    }

    public func targetDirectories(environment: ScanEnvironment) -> [URL] { [] }
    public func include(fileURL: URL, resourceValues: URLResourceValues) -> Bool { false }

    public func customScan(environment: ScanEnvironment) async -> [ScanFinding]? {
        await scan(environment: environment).findings
    }

    public func customScanResult(environment: ScanEnvironment) async throws -> ScanRuleResult? {
        await scan(environment: environment)
    }

    private func scan(environment: ScanEnvironment) async -> ScanRuleResult {
        var seen = Set<String>()
        let roots = await rootsProvider().filter { seen.insert($0.standardizedFileURL.path).inserted }
        guard !roots.isEmpty else { return ScanRuleResult(findings: []) }
        let tier = diskPressure()
        let rootPaths = roots.map(\.path)
        let scanTime = now()

        var walk = WalkBudget(entriesLeft: entryBudget, deadline: now().addingTimeInterval(timeBudget), now: now)
        var candidates: [URL] = []
        for root in roots where !Task.isCancelled && !walk.isExhausted {
            collectDependencyFolders(in: root, depth: 0, budget: &walk, into: &candidates)
        }
        var reported = Set<String>()
        let findings: [ScanFinding] = candidates.compactMap { url in
            guard !Task.isCancelled, reported.insert(url.standardizedFileURL.path).inserted,
                  let activity = ScanPolicy.reclaimableProjectDependencyActivity(
                    url, registeredRootPaths: rootPaths, tier: tier, now: scanTime) else {
                return nil
            }
            // A deadline-cut size is still reported, flagged as a lower bound.
            let sized = environment.sizeIndex.directorySizeResult(url: url)
            guard sized.bytes >= minimumBytes || !sized.isComplete else { return nil }
            return ScanFinding(
                category: category,
                riskLevel: riskLevel,
                reason: reasonText(for: url, inactiveSince: activity, tier: tier, now: scanTime),
                path: url.path,
                sizeBytes: sized.bytes,
                lastUsed: activity,
                confidence: confidence,
                isSizeComplete: sized.isComplete
            )
        }
        // Cancelled scans are discarded, so only the budget makes a result partial.
        let stoppedEarly = walk.isExhausted && !Task.isCancelled
        return ScanRuleResult(
            findings: findings,
            incompleteMessage: stoppedEarly
                ? "Stopped early (time or entry budget); some dependency folders may be missing."
                : nil
        )
    }

    private struct WalkBudget {
        var entriesLeft: Int
        let deadline: Date
        let now: @Sendable () -> Date
        private(set) var ranOut = false

        var isExhausted: Bool { ranOut }

        /// Spends one entry; false (and exhausted from then on) once entries or time run out.
        mutating func spend() -> Bool {
            guard !ranOut else { return false }
            entriesLeft -= 1
            if entriesLeft < 0 || now() >= deadline { ranOut = true }
            return !ranOut
        }
    }

    /// Dependency folders below `directory`, never descending into them, `.git`, or build output.
    private func collectDependencyFolders(in directory: URL, depth: Int, budget: inout WalkBudget, into found: inout [URL]) {
        guard depth < Self.maxDepth, !Task.isCancelled, !budget.isExhausted,
              let entries = try? FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey]
              ) else { return }
        for entry in entries {
            guard budget.spend(), !Task.isCancelled else { return }
            guard let values = try? entry.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
                  values.isDirectory == true, values.isSymbolicLink != true else { continue }
            let lower = entry.lastPathComponent.lowercased()
            if ScanPolicy.isProjectDependencyDirectory(lower) {
                found.append(entry)
            } else if !lower.hasPrefix("."), !ScanPolicy.projectLocalArtifactDirectoryNames.contains(lower),
                      !ScanPolicy.isInsideLibraryOrAppBundle(entry) {
                collectDependencyFolders(in: entry, depth: depth + 1, budget: &budget, into: &found)
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
