import Foundation

// MARK: - Version siblings (old app versions kept side by side)

extension ScanPolicy {

    /// Fewer side-by-side versions than this is normal (current + one rollback).
    public static let versionSiblingMinimumGroupSize = 3
    /// Newest versions always kept: the live one and one previous for rollback.
    public static let versionSiblingKeepCount = 2

    public static func isUnderVersionSiblingExcludedTree(_ url: URL) -> Bool {
        url.standardizedFileURL.pathComponents.contains { versionSiblingExcludedDirectoryNames.contains($0.lowercased()) }
    }

    /// Sibling directories (including `url`) whose names differ from `url`'s only in the semver token.
    static func versionSiblings(of url: URL) -> [(url: URL, name: VersionedName)] {
        guard let own = VersionedName(url.lastPathComponent) else { return [] }
        let parent = url.deletingLastPathComponent()
        let entries = (try? FileManager.default.contentsOfDirectory(
            at: parent, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey]
        )) ?? []
        return entries.compactMap { (entry: URL) -> (url: URL, name: VersionedName)? in
            guard let values = try? entry.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
                  values.isDirectory == true, values.isSymbolicLink != true,
                  let name = VersionedName(entry.lastPathComponent), name.groupKey == own.groupKey else { return nil }
            return (entry, name)
        }
    }

    /// True when `url` is one of at least `versionSiblingMinimumGroupSize` version siblings outside excluded trees.
    public static func isVersionSiblingMember(_ url: URL) -> Bool {
        guard VersionedName(url.lastPathComponent) != nil, !isUnderVersionSiblingExcludedTree(url) else { return false }
        return versionSiblings(of: url).count >= versionSiblingMinimumGroupSize
    }

    /// Cleanup-time gate: still at least two newer siblings, and no running process executes from it.
    /// Fail-closed: no process snapshot means not reclaimable.
    public static func isReclaimableVersionSibling(_ url: URL, runningExecutables: [String]?) -> Bool {
        guard let runningExecutables, isVersionSiblingMember(url),
              !containsSensitiveDataMarker(url), !isSearchIndexSensitivePath(url),
              let own = VersionedName(url.lastPathComponent) else { return false }
        let newer = versionSiblings(of: url).filter { own.version < $0.name.version }
        return newer.count >= versionSiblingKeepCount && !isExecutedFrom(url, runningExecutables: runningExecutables)
    }

    /// True when a running executable lives at or under `directory`, compared in canonical, case-folded spelling.
    public static func isExecutedFrom(_ directory: URL, runningExecutables: [String]) -> Bool {
        let base = canonicalPathURL(directory).path.lowercased()
        return runningExecutables.contains { path in
            let executable = canonicalPathURL(URL(fileURLWithPath: path)).path.lowercased()
            return executable == base || executable.hasPrefix(base + "/")
        }
    }
}
