import Foundation

/// What git says about a candidate build-output directory.
public enum GitArtifactStatus: Sendable, Equatable {
    case ignoredUntracked
    case notIgnored
    case containsTrackedFiles
    case notInRepository
    case gitUnavailable
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

    /// Read-only, non-interactive git: no index lock refresh, no credential prompts.
    static let environment = [
        "GIT_OPTIONAL_LOCKS": "0",
        "GIT_TERMINAL_PROMPT": "0",
    ]

    private struct Candidate {
        let key: String
        let relative: String
    }

    private enum RepositoryLookup {
        case repository(top: String, prefix: String)
        case notInRepository
        case failed
    }

    private let locateGit: @Sendable () async -> URL?
    private let run: Run
    private let maxArgumentBytesPerCall: Int

    public init(
        locateGit: @escaping @Sendable () async -> URL? = { await GitLocator().locate() },
        run: Run? = nil,
        maxArgumentBytesPerCall: Int = SystemGitArtifactInspector.defaultMaxArgumentBytesPerCall
    ) {
        let runner = ToolCommandRunner()
        self.locateGit = locateGit
        self.run = run ?? { await runner.run(executable: $0, arguments: $1, environment: $2) }
        self.maxArgumentBytesPerCall = maxArgumentBytesPerCall
    }

    public func statuses(for directories: [URL]) async -> [String: GitArtifactStatus] {
        guard !directories.isEmpty else { return [:] }
        guard let git = await locateGit() else {
            return Self.uniform(directories.map(\.path), .gitUnavailable)
        }

        var result: [String: GitArtifactStatus] = [:]
        var lookups: [String: RepositoryLookup] = [:]
        var candidatesByRepository: [String: [Candidate]] = [:]
        for directory in directories {
            let parent = directory.deletingLastPathComponent().path
            let lookup: RepositoryLookup
            if let cached = lookups[parent] {
                lookup = cached
            } else {
                lookup = await lookUpRepository(containing: parent, git: git)
                lookups[parent] = lookup
            }
            switch lookup {
            case .repository(let top, let prefix):
                let candidate = Candidate(key: directory.path, relative: prefix + directory.lastPathComponent)
                candidatesByRepository[top, default: []].append(candidate)
            case .notInRepository:
                result[directory.path] = .notInRepository
            case .failed:
                result[directory.path] = .failed
            }
        }

        for (top, candidates) in candidatesByRepository {
            let repositoryStatuses = await inspect(candidates, inRepository: top, git: git)
            result.merge(repositoryStatuses) { _, new in new }
        }
        return result
    }

    // MARK: - Git commands

    private func lookUpRepository(containing parent: String, git: URL) async -> RepositoryLookup {
        let arguments = Self.baseArguments(directory: parent) + ["rev-parse", "--show-toplevel", "--show-prefix"]
        guard let output = await run(git, arguments, Self.environment) else { return .failed }
        // 128 is git's "not a repository" (also unsafe ownership), which fails closed either way.
        guard output.exitCode == 0 else { return output.exitCode == 128 ? .notInRepository : .failed }
        let lines = String(decoding: output.stdout, as: UTF8.self)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
        guard let top = lines.first, !top.isEmpty else { return .failed }
        return .repository(top: top, prefix: lines.count > 1 ? lines[1] : "")
    }

    private func inspect(
        _ candidates: [Candidate],
        inRepository top: String,
        git: URL
    ) async -> [String: GitArtifactStatus] {
        let relatives = candidates.map(\.relative)
        // check-ignore only allows -z with --stdin and rejects literal pathspecs; a quoted path never matches → fails closed.
        guard let ignored = await collectPaths(
                  git: git, top: top, command: ["check-ignore", "--"], relatives: relatives,
                  acceptedExitCodes: [0, 1], separator: "\n"
              ),
              let tracked = await collectPaths(
                  git: git, top: top, command: ["--literal-pathspecs", "ls-files", "-z", "--cached", "--"], relatives: relatives,
                  acceptedExitCodes: [0], separator: "\0"
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
        separator: Character
    ) async -> [String]? {
        var paths: [String] = []
        for chunk in Self.chunks(relatives, maxBytes: maxArgumentBytesPerCall) {
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

    private static func baseArguments(directory: String) -> [String] {
        ["-c", "core.fsmonitor=false", "-c", "core.quotePath=false", "-C", directory]
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
