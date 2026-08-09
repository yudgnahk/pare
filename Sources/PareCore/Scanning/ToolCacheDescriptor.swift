import Foundation

/// How a tool's cache may be reclaimed. Discovery is always allowed; cleanup
/// authorization is a separate, narrower decision (discover broadly, clean narrowly).
public enum CacheCleanupStrategy: Sendable, Equatable {
    /// Only the tool's own CLI may reclaim this cache (e.g. `uv cache prune`).
    /// Filesystem deletion / Trash is forbidden — the tool manages locks and
    /// in-use state that Pare cannot see.
    case nativeCommandOnly(conservativeArguments: [String], fullArguments: [String]?)
    /// The exact discovered directory may be moved to Trash via the existing
    /// ScanPolicy gates (legacy whole-folder targets such as `~/.pyenv/cache`).
    case trashEligible
    /// Detect and report only — no cleanup path is validated yet.
    case reportOnly
}

/// A tool-native command (executable name + arguments) used for discovery.
/// Resolution against PATH/Homebrew locations happens at invocation time.
public struct ToolCacheCommand: Sendable, Equatable {
    public let executableName: String
    public let arguments: [String]

    public init(executableName: String, arguments: [String]) {
        self.executableName = executableName
        self.arguments = arguments
    }
}

/// Describes where a known tool keeps its cache **relative to discovered roots**,
/// plus how to ask the tool itself and how (if at all) the cache may be cleaned.
/// Descriptors contain no machine-specific absolute paths — one descriptor covers
/// platform, XDG, environment-configured, and tool-reported roots on any machine.
public struct ToolCacheDescriptor: Sendable {
    public let id: String
    public let displayName: String
    /// Child directory names checked under each resolved cache root.
    public let rootRelativeChildNames: [String]
    /// Legacy home-relative cache paths that are not cache-root children.
    public let homeRelativePaths: [String]
    /// Environment variable that overrides the cache location (absolute paths only).
    public let cacheDirEnvironmentVariable: String?
    /// Tool-native command that prints the active cache directory.
    public let nativeDiscovery: ToolCacheCommand?
    public let cleanupStrategy: CacheCleanupStrategy

    public init(
        id: String,
        displayName: String,
        rootRelativeChildNames: [String],
        homeRelativePaths: [String] = [],
        cacheDirEnvironmentVariable: String? = nil,
        nativeDiscovery: ToolCacheCommand? = nil,
        cleanupStrategy: CacheCleanupStrategy
    ) {
        self.id = id
        self.displayName = displayName
        self.rootRelativeChildNames = rootRelativeChildNames
        self.homeRelativePaths = homeRelativePaths
        self.cacheDirEnvironmentVariable = cacheDirEnvironmentVariable
        self.nativeDiscovery = nativeDiscovery
        self.cleanupStrategy = cleanupStrategy
    }

    // MARK: - Catalog

    /// uv — cache is XDG-first on modern Homebrew installs (`~/.cache/uv`).
    /// Cleanup must go through `uv cache prune` / `uv cache clean` (Phase B);
    /// until then findings are report-only (`.advanced`) and Trash is hard-blocked.
    public static let uv = ToolCacheDescriptor(
        id: "uv",
        displayName: "uv",
        rootRelativeChildNames: ["uv"],
        cacheDirEnvironmentVariable: "UV_CACHE_DIR",
        nativeDiscovery: ToolCacheCommand(executableName: "uv", arguments: ["cache", "dir"]),
        cleanupStrategy: .nativeCommandOnly(
            conservativeArguments: ["cache", "prune"],
            fullArguments: ["cache", "clean"]
        )
    )

    /// pip — native `pip cache purge` preferred; command wiring is a later phase.
    public static let pip = ToolCacheDescriptor(
        id: "pip",
        displayName: "pip",
        rootRelativeChildNames: ["pip"],
        cacheDirEnvironmentVariable: "PIP_CACHE_DIR",
        nativeDiscovery: ToolCacheCommand(executableName: "pip", arguments: ["cache", "dir"]),
        cleanupStrategy: .nativeCommandOnly(conservativeArguments: ["cache", "purge"], fullArguments: nil)
    )

    /// Poetry — cache dir is configurable; native cleanup support needs separate
    /// validation, so the descriptor stays report-only for now.
    public static let poetry = ToolCacheDescriptor(
        id: "poetry",
        displayName: "Poetry",
        rootRelativeChildNames: ["pypoetry"],
        nativeDiscovery: ToolCacheCommand(executableName: "poetry", arguments: ["config", "cache-dir"]),
        cleanupStrategy: .reportOnly
    )

    /// pyenv — not a cache-root child; the existing exact legacy target
    /// (`~/.pyenv/cache`) remains Trash-eligible via ScanPolicy markers.
    public static let pyenv = ToolCacheDescriptor(
        id: "pyenv",
        displayName: "pyenv",
        rootRelativeChildNames: [],
        homeRelativePaths: [".pyenv/cache"],
        cleanupStrategy: .trashEligible
    )

    public static let catalog: [ToolCacheDescriptor] = [.uv, .pip, .poetry, .pyenv]
}
