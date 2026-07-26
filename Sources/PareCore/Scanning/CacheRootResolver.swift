import Foundation

/// Where a cache-root candidate was discovered. Recorded on every resolved root
/// so findings can explain *why* a directory was considered (and tests can assert it).
public enum CacheRootSource: String, Sendable {
    /// Foundation's `.cachesDirectory` for the user domain (normally `~/Library/Caches`).
    case platform
    /// XDG Base Directory root — `XDG_CACHE_HOME` when absolute, else `~/.cache`.
    case xdg
    /// A tool-specific environment variable (e.g. `UV_CACHE_DIR`).
    case environment
    /// Output of a tool-native discovery command (e.g. `uv cache dir`).
    case tool

    /// Short human-readable label for finding reasons.
    public var label: String {
        switch self {
        case .platform: return "macOS cache root"
        case .xdg: return "XDG"
        case .environment: return "environment"
        case .tool: return "tool CLI"
        }
    }
}

/// A validated, canonicalized cache root plus its discovery source.
public struct ResolvedCacheRoot: Sendable, Equatable {
    public let url: URL
    public let source: CacheRootSource

    public init(url: URL, source: CacheRootSource) {
        self.url = url
        self.source = source
    }
}

/// Resolves the cache roots a tool descriptor should be checked against:
/// the platform cache directory, the XDG cache root, and (via validation helpers)
/// tool-reported or environment-configured locations.
///
/// Discovery is intentionally **broader than cleanup authorization** — a resolved
/// root only ever produces findings; it never grants Trash cleanup by itself.
///
/// All inputs are injectable so tests never consult the real user's home,
/// Foundation directories, or process environment.
public struct CacheRootResolver: Sendable {
    /// Maximum accepted length for a tool-reported path (defensive bound).
    static let maxToolReportedPathLength = 1024

    /// Injected platform cache root. Production default: Foundation `.cachesDirectory`.
    /// Tests inject a fake root (or nil) so the real `~/Library/Caches` is never used.
    public let platformCacheRoot: URL?

    /// Injected environment. Production default: the process environment.
    public let environmentVariables: [String: String]

    public init(
        platformCacheRoot: URL? = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first,
        environmentVariables: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.platformCacheRoot = platformCacheRoot
        self.environmentVariables = environmentVariables
    }

    // MARK: - Root resolution

    /// Platform + XDG cache roots for the given home directory, canonicalized,
    /// validated against dangerous roots, and deduplicated (first source wins).
    public func resolveBaseRoots(homeDirectory: URL) -> [ResolvedCacheRoot] {
        var candidates: [ResolvedCacheRoot] = []
        if let platformCacheRoot {
            candidates.append(ResolvedCacheRoot(url: platformCacheRoot, source: .platform))
        }
        candidates.append(ResolvedCacheRoot(url: xdgCacheRoot(homeDirectory: homeDirectory), source: .xdg))

        var seen = Set<String>()
        var resolved: [ResolvedCacheRoot] = []
        for candidate in candidates {
            let canonical = Self.canonicalURL(candidate.url)
            guard !Self.isDangerousRoot(canonical, homeDirectory: homeDirectory) else { continue }
            guard seen.insert(canonical.path.lowercased()).inserted else { continue }
            resolved.append(ResolvedCacheRoot(url: canonical, source: candidate.source))
        }
        return resolved
    }

    /// The XDG cache root per the XDG Base Directory specification:
    /// `XDG_CACHE_HOME` when set to a non-empty **absolute** path, else `<home>/.cache`.
    /// Relative values are ignored as the spec requires; dangerous absolute values
    /// (e.g. `/`) also fall back to the default.
    public func xdgCacheRoot(homeDirectory: URL) -> URL {
        let fallback = homeDirectory.appending(path: ".cache")
        guard let override = environmentVariables["XDG_CACHE_HOME"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !override.isEmpty,
            override.hasPrefix("/")
        else { return fallback }

        let url = Self.canonicalURL(URL(fileURLWithPath: override))
        guard !Self.isDangerousRoot(url, homeDirectory: homeDirectory) else { return fallback }
        return url
    }

    // MARK: - Validation helpers

    /// Validates raw tool/environment-supplied path text (e.g. `uv cache dir` stdout).
    /// Returns a canonical URL, or nil for empty, relative, multi-line, NUL-containing,
    /// over-long, or dangerous values. Non-fatal by design: bad output is simply ignored.
    public static func validatedToolReportedPath(_ raw: String, homeDirectory: URL) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed.count <= maxToolReportedPathLength,
              trimmed.hasPrefix("/"),
              !trimmed.contains("\n"),
              !trimmed.contains("\r"),
              !trimmed.contains("\0")
        else { return nil }

        let url = canonicalURL(URL(fileURLWithPath: trimmed))
        guard !isDangerousRoot(url, homeDirectory: homeDirectory) else { return nil }
        return url
    }

    /// Standardizes the path (removes `.` / `..` / trailing slashes) and, for paths
    /// that exist, resolves symlinks so two spellings of one physical directory
    /// deduplicate. Non-existent paths keep their standardized form — we never
    /// follow a symlink we could not verify.
    public static func canonicalURL(_ url: URL) -> URL {
        let standardized = url.standardizedFileURL
        guard FileManager.default.fileExists(atPath: standardized.path) else { return standardized }
        return standardized.resolvingSymlinksInPath()
    }

    /// Rejects roots whose contents must never be treated as cache storage:
    /// `/`, any direct child of `/` (`/System`, `/tmp`, `/Users`, `/Volumes`, …),
    /// well-known system prefixes, the bare home directory, and bare `~/Library`.
    ///
    /// Both the standardized and symlink-resolved spellings are checked so macOS's
    /// `/var → /private/var` indirection cannot smuggle a dangerous root through.
    public static func isDangerousRoot(_ url: URL, homeDirectory: URL) -> Bool {
        let standardized = url.standardizedFileURL
        // "/" has 1 path component; a direct child of "/" has 2 — both are dangerous roots.
        guard standardized.pathComponents.count > 2 else { return true }

        let candidatePaths = comparablePaths(for: standardized)
        let dangerousExactPaths: Set<String> = [
            "/private/tmp",
            "/private/var",
            "/private/etc",
            "/var/tmp",
            "/system/library",
            "/library/caches",
        ]
        if !candidatePaths.isDisjoint(with: dangerousExactPaths) { return true }

        let homePaths = comparablePaths(for: homeDirectory.standardizedFileURL)
        if !candidatePaths.isDisjoint(with: homePaths) { return true }
        let homeLibraryPaths = Set(homePaths.map { $0 + "/library" })
        if !candidatePaths.isDisjoint(with: homeLibraryPaths) { return true }
        return false
    }

    /// Lowercased standardized + symlink-resolved spellings of a path, for
    /// equality comparisons that must survive `/var → /private/var` style links.
    private static func comparablePaths(for url: URL) -> Set<String> {
        Set([
            url.path.lowercased(),
            url.resolvingSymlinksInPath().path.lowercased(),
        ])
    }
}
