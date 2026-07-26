import Foundation

/// Removes reconstructible download caches written by Ruby package managers.
/// Expands ~/.gem/ruby/*/cache/ (versioned RubyGems archives), ~/.bundle/cache/,
/// and ~/.rbenv/cache/.
/// Does NOT touch ~/.gem/ruby/*/gems/ (installed gem source) or
/// ~/.rbenv/versions/ (installed Ruby runtimes).
public struct RubyCachesRule: ScanRule {
    public let id = "ruby-caches"
    public let title = "Ruby Package Manager Caches"
    public let reason = "Ruby package manager download cache (always reconstructible)"
    public let category: ScanCategory = .developerPackageCaches
    public let riskLevel: RiskLevel = .safe
    public let confidence: Double = 0.93

    public init() {}

    public func targetDirectories(environment: ScanEnvironment) -> [URL] { [] }
    public func include(fileURL: URL, resourceValues: URLResourceValues) -> Bool { false }

    public func customScan(environment: ScanEnvironment) async -> [ScanFinding]? {
        let home = environment.homeDirectory
        var findings: [ScanFinding] = []

        // Expand ~/.gem/ruby/*/cache/
        let gemRubyDir = home.appending(path: ".gem/ruby")
        if let versionDirs = try? FileManager.default.contentsOfDirectory(
            at: gemRubyDir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) {
            for versionDir in versionDirs {
                guard (try? versionDir.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
                else { continue }
                let cacheDir = versionDir.appending(path: "cache")
                appendFinding(for: cacheDir, sizeIndex: environment.sizeIndex, to: &findings)
            }
        }

        // Fixed dotfile cache dirs
        for path in [".bundle/cache", ".rbenv/cache"] {
            appendFinding(for: home.appending(path: path), sizeIndex: environment.sizeIndex, to: &findings)
        }

        return findings
    }

    private func appendFinding(
        for url: URL,
        sizeIndex: DirectorySizeIndex,
        to findings: inout [ScanFinding]
    ) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let size = sizeIndex.directorySize(url: url)
        guard size > 0 else { return }
        let lastUsed = try? url
            .resourceValues(forKeys: [.contentModificationDateKey])
            .contentModificationDate
        findings.append(ScanFinding(
            category: category,
            riskLevel: riskLevel,
            reason: reason,
            path: url.path,
            sizeBytes: size,
            lastUsed: lastUsed,
            confidence: confidence
        ))
    }
}
