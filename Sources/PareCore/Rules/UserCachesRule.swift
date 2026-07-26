import Foundation

/// User and system app caches under ~/Library/Caches (and a few Container caches).
/// Reported as **whole top-level folders** (e.g. GeoServices, helpd) so the UI can
/// show lines like “User app cache · N items, X GB” rather than thousands of files.
/// Browser and developer package caches are owned by other rules and excluded here.
public struct UserCachesRule: ScanRule {
    public let id = "user-caches"
    public let title = "User Cache Folders"
    public let reason = "User app cache (safe to regenerate)"
    public let category: ScanCategory = .userCaches
    public let riskLevel: RiskLevel = .safe
    public let confidence: Double = 0.95

    /// Rule-ownership policy lives in `ScanPolicy` (single source of truth):
    /// top-level Library/Caches names owned by other rules or never-clean
    /// search-index stores (Spotlight / Help).
    private static let excludedTopLevelNames = ScanPolicy.userCachesExcludedTopLevelFolderNames

    public init() {}

    public func targetDirectories(environment: ScanEnvironment) -> [URL] { [] }
    public func include(fileURL: URL, resourceValues: URLResourceValues) -> Bool { false }

    public func customScan(environment: ScanEnvironment) async -> [ScanFinding]? {
        let home = environment.homeDirectory
        var findings: [ScanFinding] = []

        let cachesRoot = home.appending(path: "Library/Caches")
        findings += scanTopLevelCacheFolders(in: cachesRoot)

        // Container app caches commonly reclaimable (parity with common cleaners).
        // Intentionally omit mediaanalysisd and Library/Suggestions — deleting them
        // forces Photos/visual search and Siri Suggestions re-indexing (see ScanPolicy).
        let containerCaches: [String] = [
            "Library/Containers/com.apple.wallpaper.agent/Data/Library/Caches/com.apple.wallpaper.caches",
        ]
        for relative in containerCaches {
            findings += ScanFindingBuilder.directoryFindings(
                at: home.appending(path: relative),
                category: category,
                riskLevel: riskLevel,
                reason: "User app cache — reconstructible",
                confidence: confidence
            )
        }

        return findings
    }

    private func scanTopLevelCacheFolders(in root: URL) -> [ScanFinding] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: root.path) else { return [] }

        guard let children = try? fm.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var findings: [ScanFinding] = []
        for child in children {
            let res = try? child.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            if res?.isSymbolicLink == true { continue }
            guard res?.isDirectory == true else {
                // Small top-level files (e.g. brew_cask_catalog.json) — include if non-trivial.
                let size = FileSystemUtils.fileSize(url: child)
                guard size >= 256 * 1024 else { continue }
                findings.append(ScanFinding(
                    category: category,
                    riskLevel: riskLevel,
                    reason: reason,
                    path: child.path,
                    sizeBytes: size,
                    lastUsed: (try? child.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate,
                    confidence: confidence
                ))
                continue
            }

            let name = child.lastPathComponent.lowercased()
            if Self.excludedTopLevelNames.contains(name) { continue }
            if name.hasPrefix("com.google.") || name.hasPrefix("org.mozilla.") { continue }

            findings += ScanFindingBuilder.directoryFindings(
                at: child,
                category: category,
                riskLevel: riskLevel,
                reason: "User app cache (\(child.lastPathComponent)) — reconstructible",
                confidence: confidence
            )
        }
        return findings
    }
}
