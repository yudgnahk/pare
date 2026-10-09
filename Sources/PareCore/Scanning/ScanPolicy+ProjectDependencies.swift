import Foundation

/// How tight free space is; the tighter it is, the sooner idle projects' dependency folders are offered.
public enum DiskPressureTier: String, Sendable, CaseIterable {
    case comfortable, low, critical
}

// MARK: - Dependency folders of inactive projects
extension ScanPolicy {
    /// Days a project must be idle before its dependency folder is offered, per pressure tier.
    public static let projectDependencyInactiveDays: [DiskPressureTier: Int] = [
        .comfortable: 14, .low: 7, .critical: 3,
    ]
    /// Floor at every tier: nothing touched in the last 72 hours is ever offered.
    public static let projectDependencyMinimumInactiveSeconds: TimeInterval = 72 * 60 * 60
    /// Smaller folders (test fixtures, workspace symlink farms) are not worth a row.
    public static let projectDependencyMinimumBytes: Int64 = 1_000_000

    /// Low pressure below 15 % or 25 GB free; critical below 5 % or 10 GB, whichever hits first.
    public static let lowPressureFreeFraction = 0.15
    public static let lowPressureFreeBytes: Int64 = 25_000_000_000
    public static let criticalPressureFreeFraction = 0.05
    public static let criticalPressureFreeBytes: Int64 = 10_000_000_000

    /// Lockfiles that make a dependency folder exactly restorable, per folder name.
    public static let projectDependencyLockfiles: [String: [String]] = [
        "node_modules": ["pnpm-lock.yaml", "yarn.lock", "bun.lock", "bun.lockb", "package-lock.json"],
        "venv": ["uv.lock", "poetry.lock", "Pipfile.lock"],
        ".venv": ["uv.lock", "poetry.lock", "Pipfile.lock"],
        ".bundle": ["Gemfile.lock"],
    ]
    static let projectDependencyRestoreCommands: [String: String] = [
        "pnpm-lock.yaml": "pnpm install", "yarn.lock": "yarn install", "bun.lock": "bun install",
        "bun.lockb": "bun install", "package-lock.json": "npm ci", "uv.lock": "uv sync",
        "poetry.lock": "poetry install", "Pipfile.lock": "pipenv install", "Gemfile.lock": "bundle install",
    ]
    /// Manifests whose mtime counts as project activity (never as restore evidence on their own).
    static let projectActivityManifestNames = [
        "package.json", "pyproject.toml", "requirements.txt", "setup.py", "Pipfile", "Gemfile",
    ]
    static let projectActivityGitMarkers = ["index", "logs/HEAD", "FETCH_HEAD"]
    static let projectActivityTopLevelEntryLimit = 500

    public static func diskPressureTier(freeBytes: Int64, totalBytes: Int64) -> DiskPressureTier {
        // Unknown capacity gets the strictest threshold.
        guard totalBytes > 0 else { return .comfortable }
        let fraction = Double(freeBytes) / Double(totalBytes)
        if fraction < criticalPressureFreeFraction || freeBytes < criticalPressureFreeBytes { return .critical }
        if fraction < lowPressureFreeFraction || freeBytes < lowPressureFreeBytes { return .low }
        return .comfortable
    }

    public static func projectDependencyInactivitySeconds(for tier: DiskPressureTier) -> TimeInterval {
        let days = projectDependencyInactiveDays[tier] ?? projectDependencyInactiveDays[.comfortable] ?? 14
        return max(TimeInterval(days) * 24 * 60 * 60, projectDependencyMinimumInactiveSeconds)
    }

    /// The lockfile next to `dependency` that matches its kind, or nil.
    public static func projectDependencyLockfile(
        for dependency: URL,
        fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) -> String? {
        let project = dependency.deletingLastPathComponent().path
        return projectDependencyLockfiles[dependency.lastPathComponent.lowercased()]?
            .first { fileExists(project + "/" + $0) }
    }

    public static func projectDependencyRestoreCommand(lockfile: String) -> String? {
        projectDependencyRestoreCommands[lockfile]
    }

    /// Newest mtime among the project's git markers (its own repo, a worktree's `gitdir:`, or the enclosing
    /// repo), lockfiles, manifests and top-level entries. Dependency and build folders never count.
    public static func projectActivityDate(
        projectRoot: URL,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> Date? {
        var candidates: [URL] = []
        if let gitDir = gitDirectory(enclosing: projectRoot, homeDirectory: homeDirectory) {
            candidates += projectActivityGitMarkers.map { gitDir.appending(path: $0) }
        }
        let evidence = projectDependencyLockfiles.values.flatMap { $0 } + projectActivityManifestNames
        candidates += Set(evidence).map { projectRoot.appending(path: $0) }
        let entries = (try? FileManager.default.contentsOfDirectory(atPath: projectRoot.path)) ?? []
        candidates += entries.prefix(projectActivityTopLevelEntryLimit)
            .filter { name in
                let lower = name.lowercased()
                return lower != ".git" && lower != ".ds_store" && !isProjectDependencyDirectory(lower)
                    && !projectLocalArtifactDirectoryNames.contains(lower)
                    && !projectArtifactDirectoryNames.contains(lower)
            }
            .map { projectRoot.appending(path: $0) }
        return candidates.compactMap(modificationDate(of:)).max()
    }

    /// Cleanup- and scan-time gate. Fail-closed: a dependency name directly under a project inside a confirmed
    /// root, with a matching lockfile, idle for the tier's threshold. Unknown activity is never idle.
    public static func isReclaimableProjectDependency(
        _ url: URL,
        registeredRootPaths: [String],
        tier: DiskPressureTier,
        now: Date,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> Bool {
        guard isProjectDependencyDirectory(url.lastPathComponent) else { return false }
        let project = url.deletingLastPathComponent()
        guard project.path != "/", !isEqualToOrDescendant(candidate: homeDirectory, root: project) else { return false }
        let underRoot = registeredRootPaths.contains { rootPath in
            !rootPath.isEmpty && isEqualToOrDescendant(candidate: project, root: URL(fileURLWithPath: rootPath))
        }
        guard underRoot, projectDependencyLockfile(for: url) != nil,
              let activity = projectActivityDate(projectRoot: project, homeDirectory: homeDirectory) else { return false }
        return now.timeIntervalSince(activity) >= projectDependencyInactivitySeconds(for: tier)
    }

    /// The git directory for `projectRoot`: its own `.git`, a worktree's `gitdir:` target, or the nearest
    /// enclosing repo's. Stops at the home directory so a dotfile repo never counts.
    static func gitDirectory(enclosing projectRoot: URL, homeDirectory: URL) -> URL? {
        let fm = FileManager.default
        var directory = projectRoot
        for _ in 0..<projectRootEvidenceMaxAncestors {
            if directory.path == "/" || directory.standardizedFileURL.path == homeDirectory.standardizedFileURL.path {
                return nil
            }
            let dotGit = directory.appending(path: ".git")
            var isDirectory: ObjCBool = false
            if fm.fileExists(atPath: dotGit.path, isDirectory: &isDirectory) {
                return isDirectory.boolValue ? dotGit : worktreeGitDirectory(dotGitFile: dotGit)
            }
            directory = directory.deletingLastPathComponent()
        }
        return nil
    }

    private static func worktreeGitDirectory(dotGitFile: URL) -> URL? {
        guard let text = try? String(contentsOf: dotGitFile, encoding: .utf8),
              let line = text.split(whereSeparator: \.isNewline).first, line.hasPrefix("gitdir:") else { return nil }
        let target = line.dropFirst("gitdir:".count).trimmingCharacters(in: .whitespaces)
        guard !target.isEmpty else { return nil }
        return target.hasPrefix("/")
            ? URL(fileURLWithPath: target)
            : dotGitFile.deletingLastPathComponent().appending(path: target).standardizedFileURL
    }

    private static func modificationDate(of url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }
}

/// Live disk-pressure tier of the volume holding `volume`; unreadable capacity gives the strictest tier.
public enum DiskPressure {
    public static func current(
        volume: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> DiskPressureTier {
        let keys: Set<URLResourceKey> = [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey]
        guard let values = try? volume.resourceValues(forKeys: keys),
              let free = values.volumeAvailableCapacityForImportantUsage,
              let total = values.volumeTotalCapacity else { return .comfortable }
        return ScanPolicy.diskPressureTier(freeBytes: free, totalBytes: Int64(total))
    }
}
