import Foundation

/// pnpm store folders (`…/pnpm/store/v<M>`) older than the version the installed pnpm uses. Whole-folder,
/// `.review`: projects reinstall from the new store. Reports nothing when the active version is unknown.
public struct PnpmOldStoreRule: ScanRule {
    public let id = "pnpm-old-store-versions"
    public let title = "Old pnpm Store Versions"
    public let reason = "pnpm store version the installed pnpm no longer uses"
    public let category: ScanCategory = .developerPackageCaches
    public let riskLevel: RiskLevel = .review
    public let confidence: Double = 0.9

    /// Resolves the active store (`…/store/v<N>`) for a home directory, or nil when it cannot be determined.
    public typealias ActiveStore = @Sendable (URL) async -> URL?

    private let activeStore: ActiveStore

    public init(activeStore: ActiveStore? = nil) {
        self.activeStore = activeStore ?? { home in await PnpmStoreLocator.activeStore(home: home) }
    }

    public func targetDirectories(environment: ScanEnvironment) -> [URL] { [] }
    public func include(fileURL: URL, resourceValues: URLResourceValues) -> Bool { false }

    public func customScan(environment: ScanEnvironment) async -> [ScanFinding]? {
        guard let active = await activeStore(environment.homeDirectory),
              let activeVersion = ScanPolicy.pnpmStoreVersion(active.lastPathComponent) else { return [] }
        let root = active.deletingLastPathComponent()
        let entries = (try? FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .contentModificationDateKey]
        )) ?? []
        return entries
            .filter { ScanPolicy.isReclaimableOldPnpmStore($0, activeStore: active) }
            .compactMap { entry -> ScanFinding? in
                let size = environment.sizeIndex.directorySize(url: entry)
                guard size > 0, let version = ScanPolicy.pnpmStoreVersion(entry.lastPathComponent) else { return nil }
                return ScanFinding(
                    category: category,
                    riskLevel: riskLevel,
                    reason: "Old pnpm store v\(version) — pnpm now uses v\(activeVersion); projects reinstall from the new store",
                    path: entry.path,
                    sizeBytes: size,
                    lastUsed: try? entry.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                    confidence: confidence
                )
            }
    }
}

/// Finds the active pnpm store by asking pnpm itself (`pnpm store path`), bounded and non-fatal.
public enum PnpmStoreLocator {
    /// Where standalone pnpm installs keep the binary, besides PATH and Homebrew.
    static func binaryDirectories(home: URL, environment: [String: String]) -> [String] {
        [environment["PNPM_HOME"], home.appending(path: "Library/pnpm").path, home.appending(path: ".local/share/pnpm").path]
            .compactMap { $0 }
    }

    /// The last absolute line of `pnpm store path` output, when it ends in a `v<N>` folder.
    static func activeStore(fromStorePathOutput output: String?) -> URL? {
        guard let line = output?
            .split(whereSeparator: \.isNewline)
            .map({ $0.trimmingCharacters(in: .whitespaces) })
            .last(where: { !$0.isEmpty }),
              line.hasPrefix("/") else { return nil }
        let url = URL(fileURLWithPath: line).standardizedFileURL
        return ScanPolicy.pnpmStoreVersion(url.lastPathComponent) == nil ? nil : url
    }

    /// Nil when pnpm is absent, fails, times out, or prints something unexpected.
    public static func activeStore(home: URL) async -> URL? {
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = ([environment["PATH"]] + binaryDirectories(home: home, environment: environment).map { Optional($0) })
            .compactMap { $0 }
            .joined(separator: ":")
        let runner = ToolCommandRunner()
        guard let pnpm = runner.resolveExecutable(named: "pnpm", environmentVariables: environment) else { return nil }
        return activeStore(fromStorePathOutput: await runner.capture(executable: pnpm, arguments: ["store", "path"]))
    }
}
