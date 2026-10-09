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
    /// Entries and seconds the activity walk may spend per project; a project too big to read counts as active.
    public static let projectActivityEntryBudget = 20_000
    public static let projectActivityTimeBudget: TimeInterval = 2
    static let projectActivityDeadlineCheckInterval = 256

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
    /// repo) and every file below it, skipping dependency and build folders. Nil when unknown, or when the walk
    /// runs out of budget or hits an unreadable folder: callers treat nil as active.
    public static func projectActivityDate(
        projectRoot: URL,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        entryBudget: Int = projectActivityEntryBudget,
        timeBudget: TimeInterval = projectActivityTimeBudget,
        now: () -> Date = { Date() }
    ) -> Date? {
        var markerDates: [Date] = []
        if let gitDir = gitDirectory(enclosing: projectRoot, homeDirectory: homeDirectory) {
            markerDates = projectActivityGitMarkers.compactMap { modificationDate(of: gitDir.appending(path: $0)) }
        }
        let walk = newestFileModification(
            under: projectRoot, entryBudget: entryBudget, deadline: now().addingTimeInterval(timeBudget), now: now
        )
        guard case .finished(let newestFile) = walk else { return nil }
        return (markerDates + [newestFile].compactMap { $0 }).max()
    }

    private enum ActivityWalk {
        case finished(Date?)
        case gaveUp
    }

    /// Directory mtimes are ignored: creating a folder (or a tool touching one) is not editing the project.
    private static func newestFileModification(
        under root: URL, entryBudget: Int, deadline: Date, now: () -> Date
    ) -> ActivityWalk {
        let keys: [URLResourceKey] = [.isDirectoryKey, .isRegularFileKey, .contentModificationDateKey]
        var unreadable = false
        guard let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: keys, options: [], errorHandler: { _, _ in
                unreadable = true
                return false
            }
        ) else { return .gaveUp }
        var newest: Date?
        var visited = 0
        for case let entry as URL in enumerator {
            visited += 1
            if visited > entryBudget || Task.isCancelled
                || (visited % projectActivityDeadlineCheckInterval == 0 && now() >= deadline) {
                return .gaveUp
            }
            let lower = entry.lastPathComponent.lowercased()
            guard let values = try? entry.resourceValues(forKeys: Set(keys)) else { return .gaveUp }
            if values.isDirectory == true {
                if lower == ".git" || isProjectDependencyDirectory(lower) || projectArtifactDirectoryNames.contains(lower) {
                    enumerator.skipDescendants()
                }
                continue
            }
            guard values.isRegularFile == true, lower != ".git", lower != ".ds_store",
                  let modified = values.contentModificationDate else { continue }
            newest = max(newest ?? modified, modified)
        }
        return unreadable || now() >= deadline ? .gaveUp : .finished(newest)
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
        reclaimableProjectDependencyActivity(
            url, registeredRootPaths: registeredRootPaths, tier: tier, now: now, homeDirectory: homeDirectory
        ) != nil
    }

    /// The project's last activity when `isReclaimableProjectDependency` holds, so callers walk the project once.
    public static func reclaimableProjectDependencyActivity(
        _ url: URL,
        registeredRootPaths: [String],
        tier: DiskPressureTier,
        now: Date,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> Date? {
        guard isProjectDependencyDirectory(url.lastPathComponent), !isInsideLibraryOrAppBundle(url) else { return nil }
        let project = url.deletingLastPathComponent()
        guard project.path != "/", !isEqualToOrDescendant(candidate: homeDirectory, root: project) else { return nil }
        let underRoot = registeredRootPaths.contains { rootPath in
            !rootPath.isEmpty && isEqualToOrDescendant(candidate: project, root: URL(fileURLWithPath: rootPath))
        }
        guard underRoot, projectDependencyLockfile(for: url) != nil,
              let activity = projectActivityDate(projectRoot: project, homeDirectory: homeDirectory),
              now.timeIntervalSince(activity) >= projectDependencyInactivitySeconds(for: tier) else { return nil }
        return activity
    }

    /// App data and bundled runtimes keep their own `node_modules`/`venv`; a manual root can reach both.
    /// Case-insensitive, like the default APFS volume, so `~/library/…` is caught too.
    public static func isInsideLibraryOrAppBundle(_ url: URL) -> Bool {
        url.standardizedFileURL.pathComponents.contains { component in
            let lower = component.lowercased()
            return lower == "library" || lower.hasSuffix(".app")
        }
    }

    /// A tracked or unignored dependency folder may be vendored on purpose; no answer fails closed.
    public static func gitEvidenceAllows(dependency url: URL, status: GitArtifactStatus?) -> Bool {
        status == .ignoredUntracked || status == .notInRepository
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
