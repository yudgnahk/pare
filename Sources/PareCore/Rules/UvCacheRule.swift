import Foundation

/// Detects uv's package/tool cache wherever it actually lives — platform cache
/// root, XDG root (`~/.cache/uv` on modern Homebrew installs), `UV_CACHE_DIR`,
/// or the directory `uv cache dir` reports — and emits one whole-folder finding
/// per unique physical directory.
///
/// **Report-only (Phase A):** findings are `.advanced`, so `CleanupEngine`
/// hard-blocks Trash deletion. uv requires its own cache commands
/// (`uv cache prune` / `uv cache clean`) because it manages locks and in-use
/// state Pare cannot see; the native Maintenance action arrives in Phase B.
public struct UvCacheRule: ScanRule {
    public let id = "uv-cache"
    public let title = "uv Cache"
    public let reason = "uv cache — reclaim with uv's cache command (report-only)"
    public let category: ScanCategory = .developerPackageCaches
    public let riskLevel: RiskLevel = .advanced
    public let confidence: Double = 0.9

    /// Returns raw `uv cache dir` stdout, or nil when uv is absent/failed/timed out.
    public typealias ToolCacheDirProvider = @Sendable () async -> String?

    private let resolver: CacheRootResolver
    private let toolCacheDirProvider: ToolCacheDirProvider

    public init(
        resolver: CacheRootResolver = CacheRootResolver(),
        toolCacheDirProvider: ToolCacheDirProvider? = nil
    ) {
        self.resolver = resolver
        self.toolCacheDirProvider = toolCacheDirProvider
            ?? Self.makeDefaultProvider(environmentVariables: resolver.environmentVariables)
    }

    public func targetDirectories(environment: ScanEnvironment) -> [URL] { [] }
    public func include(fileURL: URL, resourceValues: URLResourceValues) -> Bool { false }

    public func customScan(environment: ScanEnvironment) async -> [ScanFinding]? {
        let home = environment.homeDirectory
        let descriptor = ToolCacheDescriptor.uv

        // Candidate order = explanatory confidence: the tool's own answer first
        // (it sees the same configuration uv uses), then environment override,
        // then static XDG/platform roots as fallbacks for machines where uv is
        // absent or not executable from a GUI context. Dedupe keeps the first.
        var candidates: [(url: URL, sourceLabel: String)] = []

        if let raw = await toolCacheDirProvider(),
           let url = CacheRootResolver.validatedToolReportedPath(raw, homeDirectory: home) {
            candidates.append((url, "uv CLI"))
        }

        if let envVar = descriptor.cacheDirEnvironmentVariable,
           let raw = resolver.environmentVariables[envVar],
           let url = CacheRootResolver.validatedToolReportedPath(raw, homeDirectory: home) {
            candidates.append((url, CacheRootSource.environment.label))
        }

        for root in resolver.resolveBaseRoots(homeDirectory: home) {
            for child in descriptor.rootRelativeChildNames {
                candidates.append((root.url.appending(path: child), root.source.label))
            }
        }

        var seenCanonicalPaths = Set<String>()
        var findings: [ScanFinding] = []
        for candidate in candidates {
            let canonical = CacheRootResolver.canonicalURL(candidate.url)
            guard !CacheRootResolver.isDangerousRoot(canonical, homeDirectory: home) else { continue }
            guard seenCanonicalPaths.insert(canonical.path.lowercased()).inserted else { continue }

            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: canonical.path, isDirectory: &isDirectory),
                  isDirectory.boolValue else { continue }

            let size = FileSystemUtils.directorySize(url: canonical)
            guard size > 0 else { continue }

            let lastUsed = try? canonical
                .resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate
            findings.append(ScanFinding(
                category: category,
                riskLevel: riskLevel,
                reason: "uv cache (\(candidate.sourceLabel)) — reclaim with `uv cache prune` or `uv cache clean`",
                path: canonical.path,
                sizeBytes: size,
                lastUsed: lastUsed,
                confidence: confidence
            ))
        }
        return findings
    }

    // MARK: - Default tool discovery

    /// Default provider runs `uv cache dir` with a short timeout and null stdin.
    /// Skipped entirely (returns nil) when uv is not installed. Never fatal.
    private static func makeDefaultProvider(
        environmentVariables: [String: String]
    ) -> ToolCacheDirProvider {
        let command = ToolCacheDescriptor.uv.nativeDiscovery
        return {
            guard let command else { return nil }
            return await ToolCommandRunner().captureOutput(
                of: command,
                environmentVariables: environmentVariables
            )
        }
    }
}
