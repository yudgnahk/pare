import Foundation

/// What git says about a candidate build-output directory.
public enum GitArtifactStatus: Sendable, Equatable {
    case ignoredUntracked
    case notIgnored
    case containsTrackedFiles
    case notInRepository
    case gitUnavailable
    /// Git predates `--no-lazy-fetch` (2.45), so nothing could be checked safely; fails closed like `.failed`.
    case gitTooOld
    case failed
}

/// Reports git evidence for candidate artifact directories, keyed by each input URL's `path`.
public protocol GitArtifactInspecting: Sendable {
    func statuses(for directories: [URL]) async -> [String: GitArtifactStatus]
}

/// Asks the user's git, batching one `check-ignore` and one `ls-files` per repository.
public struct SystemGitArtifactInspector: GitArtifactInspecting {
    public typealias Run = @Sendable (URL, [String], [String: String]) async -> (exitCode: Int32, stdout: Data)?

    /// Far below macOS ARG_MAX (1 MiB, shared with the environment).
    public static let defaultMaxArgumentBytesPerCall = 128 * 1024

    /// Budget for one `statuses(for:)` call; a git call already running may overrun it by its own 3 s timeout.
    public static let defaultTotalDeadlineSeconds: TimeInterval = 20

    /// Git's whole environment, nothing inherited: `GIT_DIR`, `GIT_CEILING_DIRECTORIES` or `GIT_EXEC_PATH` would redirect it.
    /// No index lock refresh, no credential prompts, no transport. `HOME` keeps the user's global ignores and `safe.directory`.
    static let environment: [String: String] = {
        let fixed = [
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
            "LC_ALL": "C",
            "GIT_OPTIONAL_LOCKS": "0",
            "GIT_TERMINAL_PROMPT": "0",
            "GIT_ALLOW_PROTOCOL": "none",
        ]
        return NSHomeDirectoryForUser(NSUserName()).map { fixed.merging(["HOME": $0]) { current, _ in current } } ?? fixed
    }()

    static let usageErrorExitCode: Int32 = 129

    private struct Candidate {
        let key: String
        let relative: String
    }

    private enum RepositoryLookup {
        case repository(top: String, prefix: String)
        case notInRepository
        case gitTooOld
        case failed
    }

    private let locateGit: @Sendable () async -> URL?
    private let run: Run
    private let maxArgumentBytesPerCall: Int
    private let totalDeadline: TimeInterval
    private let now: @Sendable () -> Date

    public init(
        locateGit: @escaping @Sendable () async -> URL? = { await GitLocator().locate() },
        run: Run? = nil,
        maxArgumentBytesPerCall: Int = SystemGitArtifactInspector.defaultMaxArgumentBytesPerCall,
        totalDeadline: TimeInterval = SystemGitArtifactInspector.defaultTotalDeadlineSeconds,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        let runner = ToolCommandRunner()
        self.locateGit = locateGit
        self.run = run ?? { await runner.run(executable: $0, arguments: $1, exactEnvironment: $2) }
        self.maxArgumentBytesPerCall = maxArgumentBytesPerCall
        self.totalDeadline = totalDeadline
        self.now = now
    }

    /// Directories git could not reach before the total deadline report `.failed`, so they stay uncleanable.
    public func statuses(for directories: [URL]) async -> [String: GitArtifactStatus] {
        guard !directories.isEmpty else { return [:] }
        let deadline = now().addingTimeInterval(totalDeadline)
        guard let git = await locateGit() else {
            return Self.uniform(directories.map(\.path), .gitUnavailable)
        }

        let supportCache = GitSupportCache()
        var result: [String: GitArtifactStatus] = [:]
        var lookups: [String: RepositoryLookup] = [:]
        var knownTops: Set<String> = []
        var candidatesByRepository: [String: [Candidate]] = [:]
        for directory in directories {
            let parent = directory.deletingLastPathComponent().path
            let lookup: RepositoryLookup
            if supportCache.value(for: git.path) == true {
                lookup = .gitTooOld
            } else if let cached = lookups[parent] {
                lookup = cached
            } else if let top = Self.enclosingKnownTop(of: parent, knownTops: knownTops) {
                lookup = .repository(top: top, prefix: parent == top ? "" : String(parent.dropFirst(top.count + 1)) + "/")
                lookups[parent] = lookup
            } else if now() >= deadline {
                lookup = .failed
            } else {
                lookup = await lookUpRepository(containing: parent, git: git, support: supportCache)
                lookups[parent] = lookup
                if case .repository(let top, _) = lookup { knownTops.insert(top) }
            }
            switch lookup {
            case .repository(let top, let prefix):
                let candidate = Candidate(key: directory.path, relative: prefix + directory.lastPathComponent)
                if GitCandidateChecks.holdsOwnGitEntry(directory.path)
                    || !GitCandidateChecks.isInside(top: top, relative: candidate.relative, directory: directory.path) {
                    result[directory.path] = .failed
                } else {
                    candidatesByRepository[top, default: []].append(candidate)
                }
            case .notInRepository:
                result[directory.path] = GitCandidateChecks.holdsOwnGitEntry(directory.path) ? .failed : .notInRepository
            case .gitTooOld:
                result[directory.path] = .gitTooOld
            case .failed:
                result[directory.path] = .failed
            }
        }

        for (top, candidates) in candidatesByRepository {
            let repositoryStatuses = await inspect(candidates, inRepository: top, git: git, deadline: deadline)
            result.merge(repositoryStatuses) { _, new in new }
        }
        return result
    }

    // MARK: - Git commands

    private func lookUpRepository(containing parent: String, git: URL, support: GitSupportCache) async -> RepositoryLookup {
        let arguments = Self.baseArguments(directory: parent) + ["rev-parse", "--show-toplevel", "--show-prefix"]
        guard let output = await run(git, arguments, Self.environment) else { return .failed }
        guard output.exitCode == 0 else {
            if output.exitCode == Self.usageErrorExitCode, await isTooOld(git, support: support) { return .gitTooOld }
            return output.exitCode == 128 && GitRepositoryAbsence.isProven(at: parent) ? .notInRepository : .failed
        }
        let lines = String(decoding: output.stdout, as: UTF8.self)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
        guard let top = lines.first, !top.isEmpty else { return .failed }
        return .repository(top: top, prefix: lines.count > 1 ? lines[1] : "")
    }

    /// Exit 129 is git rejecting an option; only a version below 2.45 makes it ours, anything else stays `.failed`.
    private func isTooOld(_ git: URL, support: GitSupportCache) async -> Bool {
        if let known = support.value(for: git.path) { return known }
        guard let output = await run(git, ["--version"], Self.environment), output.exitCode == 0,
              let version = GitVersion(output: String(decoding: output.stdout, as: UTF8.self)) else { return false }
        let tooOld = version < GitVersion.noLazyFetchSupport
        support.store(tooOld, for: git.path)
        return tooOld
    }

    private func inspect(
        _ candidates: [Candidate],
        inRepository top: String,
        git: URL,
        deadline: Date
    ) async -> [String: GitArtifactStatus] {
        let relatives = candidates.map(\.relative)
        // check-ignore only allows -z with --stdin and rejects literal pathspecs; a quoted path never matches → fails closed.
        guard let ignored = await collectPaths(
                  git: git, top: top, command: ["check-ignore", "--"], relatives: relatives,
                  acceptedExitCodes: [0, 1], separator: "\n", deadline: deadline
              ),
              let tracked = await collectPaths(
                  git: git, top: top, command: ["--literal-pathspecs", "ls-files", "-z", "--cached", "--"], relatives: relatives,
                  acceptedExitCodes: [0], separator: "\0", deadline: deadline
              )
        else { return Self.uniform(candidates.map(\.key), .failed) }

        let ignoredSet = Set(ignored)
        let trackedPaths = tracked.map(Self.comparable)
        var result: [String: GitArtifactStatus] = [:]
        for candidate in candidates {
            let relative = Self.comparable(candidate.relative)
            if trackedPaths.contains(where: { $0 == relative || $0.hasPrefix(relative + "/") }) {
                result[candidate.key] = .containsTrackedFiles
            } else {
                result[candidate.key] = ignoredSet.contains(candidate.relative) ? .ignoredUntracked : .notIgnored
            }
        }
        return result
    }

    private func collectPaths(
        git: URL,
        top: String,
        command: [String],
        relatives: [String],
        acceptedExitCodes: Set<Int32>,
        separator: Character,
        deadline: Date
    ) async -> [String]? {
        var paths: [String] = []
        for chunk in Self.chunks(relatives, maxBytes: maxArgumentBytesPerCall) {
            guard now() < deadline else { return nil }
            let arguments = Self.baseArguments(directory: top) + command + chunk
            guard let output = await run(git, arguments, Self.environment),
                  acceptedExitCodes.contains(output.exitCode) else { return nil }
            paths += String(decoding: output.stdout, as: UTF8.self)
                .split(separator: separator)
                .map(String.init)
        }
        return paths
    }

    // MARK: - Helpers

    /// A repository already found holds `parent` when no `.git` (nested repo, submodule, worktree) sits between them.
    /// Spellings that differ from git's toplevel (`/var` vs `/private/var`) never match and fall back to `rev-parse`.
    private static func enclosingKnownTop(of parent: String, knownTops: Set<String>) -> String? {
        var url = URL(fileURLWithPath: parent)
        guard !knownTops.isEmpty, !url.pathComponents.contains(where: { $0.lowercased() == ".git" }) else { return nil }
        while url.path != "/" {
            if knownTops.contains(url.path) { return url.path }
            if FileManager.default.fileExists(atPath: url.path + "/.git") { return nil }
            url = url.deletingLastPathComponent()
        }
        return nil
    }

    /// With these, nothing a scanned repo's config names can run: a lazy fetch and fsmonitor are the two ways
    /// `check-ignore` and `ls-files` reach one. A git too old for the flag exits 129 and reads `.gitTooOld`.
    private static func baseArguments(directory: String) -> [String] {
        ["--no-pager", "--no-lazy-fetch", "-c", "core.fsmonitor=false", "-c", "core.quotePath=false", "-C", directory]
    }

    /// Case- and normalization-insensitive, so a spelling mismatch reports "tracked" (fail closed).
    private static func comparable(_ path: String) -> String {
        path.precomposedStringWithCanonicalMapping.lowercased()
    }

    private static func uniform(_ keys: [String], _ status: GitArtifactStatus) -> [String: GitArtifactStatus] {
        Dictionary(keys.map { ($0, status) }, uniquingKeysWith: { first, _ in first })
    }

    static func chunks(_ items: [String], maxBytes: Int) -> [[String]] {
        var result: [[String]] = []
        var current: [String] = []
        var currentBytes = 0
        for item in items {
            let cost = item.utf8.count + 1
            if !current.isEmpty, currentBytes + cost > maxBytes {
                result.append(current)
                current = []
                currentBytes = 0
            }
            current.append(item)
            currentBytes += cost
        }
        if !current.isEmpty { result.append(current) }
        return result
    }
}
